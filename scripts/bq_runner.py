#!/usr/bin/env python3
"""Run, validate, and reconcile this project's BigQuery SQL models.

The runner deliberately uses only the Python standard library. BigQuery work is
delegated to the official `bq` command so the project does not depend on the
system Python version.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import glob
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


ROOT = Path(__file__).resolve().parents[1]
LOCAL_SDK = ROOT / ".tools" / "google-cloud-sdk"
MODEL_DIR = ROOT / "sql" / "models"
MART_DIR = ROOT / "sql" / "marts"
QA_DIR = ROOT / "sql" / "qa"
ANALYSIS_DIR = ROOT / "sql" / "analysis"
RESULT_ROOT = ROOT / "data" / "interim" / "query_results"
DEFAULT_ENV_FILE = ROOT / ".env"

PROJECT_PATTERN = re.compile(r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$")
# The value shipped in .env.example; it is syntactically valid, so reject it
# explicitly instead of letting the first bq call fail with a vaguer error.
PLACEHOLDER_PROJECT_ID = "your-google-cloud-project-id"
DATASET_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,1023}$")
LOCATION_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")
CSV_HEADER_FIELD_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


class RunnerError(RuntimeError):
    """An actionable runner failure."""


def load_env_file(path: Path) -> None:
    """Load simple KEY=VALUE pairs without overriding exported variables."""
    if not path.exists():
        return

    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise RunnerError(
                f"{path}:{line_number} is not a KEY=VALUE assignment."
            )
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if (
            len(value) >= 2
            and value[0] == value[-1]
            and value[0] in {"'", '"'}
        ):
            value = value[1:-1]
        os.environ.setdefault(key, value)


def executable_version(path: str) -> Optional[Tuple[int, int]]:
    try:
        result = subprocess.run(
            [
                path,
                "-c",
                (
                    "import sys;"
                    "print(f'{sys.version_info.major}.{sys.version_info.minor}')"
                ),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        major, minor = result.stdout.strip().split(".", 1)
        return int(major), int(minor)
    except (OSError, subprocess.CalledProcessError, ValueError):
        return None


def cloud_sdk_environment() -> Dict[str, str]:
    """Return an environment with a gcloud-compatible Python when required."""
    env = os.environ.copy()
    local_bin = LOCAL_SDK / "bin"
    if local_bin.exists():
        env["PATH"] = f"{local_bin}{os.pathsep}{env.get('PATH', '')}"

    configured = env.get("CLOUDSDK_PYTHON")
    if configured:
        configured_version = executable_version(configured)
        if configured_version and configured_version >= (3, 10):
            return env

    candidates: List[str] = []
    for name in ("python3.14", "python3.13", "python3.12", "python3.11", "python3.10"):
        resolved = shutil.which(name)
        if resolved:
            candidates.append(resolved)

    candidates.extend(
        glob.glob(
            str(
                Path.home()
                / ".cache"
                / "codex-runtimes"
                / "*"
                / "dependencies"
                / "python"
                / "bin"
                / "python3"
            )
        )
    )
    candidates.append(sys.executable)

    for candidate in candidates:
        version = executable_version(candidate)
        if version and version >= (3, 10):
            env["CLOUDSDK_PYTHON"] = candidate
            return env

    raise RunnerError(
        "Google Cloud CLI needs Python 3.10+. Install a supported Python or set "
        "CLOUDSDK_PYTHON to its executable."
    )


def find_tool(name: str) -> str:
    resolved = shutil.which(name)
    if resolved:
        return resolved

    local = LOCAL_SDK / "bin" / name
    if local.exists():
        return str(local)

    raise RunnerError(
        f"Cannot find `{name}`. Install Google Cloud CLI or place it under "
        f"{LOCAL_SDK}."
    )


def run_process(
    command: Sequence[str],
    *,
    input_text: Optional[str] = None,
    capture: bool = True,
    check: bool = True,
) -> subprocess.CompletedProcess:
    result = subprocess.run(
        list(command),
        input=input_text,
        text=True,
        capture_output=capture,
        env=cloud_sdk_environment(),
    )
    if check and result.returncode != 0:
        if capture:
            if result.stdout:
                print(result.stdout.rstrip(), file=sys.stderr)
            if result.stderr:
                print(result.stderr.rstrip(), file=sys.stderr)
        raise RunnerError(
            f"Command failed with exit code {result.returncode}: "
            f"{' '.join(command)}"
        )
    return result


def require_config() -> Dict[str, str]:
    project_id = os.environ.get("BQ_PROJECT_ID", "").strip()
    dataset_id = os.environ.get("BQ_DATASET_ID", "").strip()
    location = os.environ.get("BQ_LOCATION", "US").strip()
    max_bytes = os.environ.get("BQ_MAX_BYTES_BILLED", "10000000000").strip()

    if (
        project_id == PLACEHOLDER_PROJECT_ID
        or not PROJECT_PATTERN.fullmatch(project_id)
    ):
        raise RunnerError(
            "Set a real BQ_PROJECT_ID in .env. Copy .env.example to .env, then "
            "replace the placeholder with the project shown in BigQuery Studio."
        )
    if not DATASET_PATTERN.fullmatch(dataset_id):
        raise RunnerError(
            "BQ_DATASET_ID must contain only letters, numbers, and underscores "
            "and must start with a letter or underscore."
        )
    if not LOCATION_PATTERN.fullmatch(location):
        raise RunnerError("BQ_LOCATION contains unsupported characters.")
    if not max_bytes.isdigit() or int(max_bytes) <= 0:
        raise RunnerError("BQ_MAX_BYTES_BILLED must be a positive integer.")

    return {
        "project_id": project_id,
        "dataset_id": dataset_id,
        "location": location,
        "max_bytes": max_bytes,
    }


def render_sql(path: Path, config: Dict[str, str]) -> str:
    sql = path.read_text(encoding="utf-8")
    rendered = (
        sql.replace("{{ project_id }}", config["project_id"])
        .replace("{{ dataset_id }}", config["dataset_id"])
        .replace("{{ location }}", config["location"])
    )
    unresolved = sorted(set(re.findall(r"\{\{\s*[^}]+\s*\}\}", rendered)))
    if unresolved:
        raise RunnerError(
            f"{path} contains unresolved template values: {', '.join(unresolved)}"
        )
    return rendered


def bq_global_args(config: Dict[str, str], output_format: str) -> List[str]:
    return [
        find_tool("bq"),
        f"--project_id={config['project_id']}",
        f"--location={config['location']}",
        f"--format={output_format}",
        "--quiet",
    ]


def execute_sql(
    path: Path,
    config: Dict[str, str],
    *,
    dry_run: bool = False,
    output_format: str = "csv",
) -> str:
    sql = render_sql(path, config)
    command = bq_global_args(config, output_format)
    command.extend(
        [
            "query",
            "--use_legacy_sql=false",
            f"--maximum_bytes_billed={config['max_bytes']}",
            "--max_rows=100000",
        ]
    )
    if dry_run:
        command.append("--dry_run")
    result = run_process(command, input_text=sql)
    if output_format == "csv" and not dry_run:
        return extract_csv_payload(result.stdout)
    return result.stdout


def extract_csv_payload(output: str) -> str:
    """Remove bq script progress text before the final CSV result set.

    The bq CLI prints temporary-table statements and creation messages to
    stdout for multi-statement scripts, even with --quiet and --format=csv.
    Find the first identifier-only CSV header whose remaining rows all match
    its width. Ordinary single-statement CSV output is returned unchanged.
    """
    lines = output.splitlines()
    for index, line in enumerate(lines):
        try:
            header = next(csv.reader([line]))
        except (csv.Error, StopIteration):
            continue
        if len(header) < 2 or not all(
            CSV_HEADER_FIELD_PATTERN.fullmatch(field) for field in header
        ):
            continue
        try:
            rows = list(csv.reader(lines[index:]))
        except csv.Error:
            continue
        if rows and all(
            len(row) == len(header) for row in rows if any(row)
        ):
            return "\n".join(lines[index:]) + "\n"
    return output


def model_object_spec(
    path: Path,
    config: Dict[str, str],
) -> Tuple[str, str]:
    rendered = render_sql(path, config)
    match = re.search(
        r"CREATE\s+OR\s+REPLACE\s+(VIEW|TABLE)\s+`([^`]+)`",
        rendered,
        flags=re.IGNORECASE,
    )
    if not match:
        raise RunnerError(
            f"Cannot identify a CREATE OR REPLACE VIEW/TABLE target in {path}."
        )
    return match.group(1).upper(), match.group(2)


def migrate_model_object_type(path: Path, config: Dict[str, str]) -> None:
    """Drop a derived object only when its existing type blocks replacement."""
    desired_type, full_name = model_object_spec(path, config)
    project_id, dataset_id, object_name = full_name.split(".", 2)
    object_ref = f"{project_id}:{dataset_id}.{object_name}"
    show_command = bq_global_args(config, "prettyjson")
    show_command.extend(["show", object_ref])
    shown = run_process(show_command, check=False)
    if shown.returncode != 0:
        return

    try:
        current_type = json.loads(shown.stdout).get("type", "").upper()
    except json.JSONDecodeError as exc:
        raise RunnerError(
            f"Cannot parse BigQuery metadata for {object_ref}."
        ) from exc

    if not current_type or current_type == desired_type:
        return
    if current_type not in {"TABLE", "VIEW"}:
        raise RunnerError(
            f"{object_ref} has unsupported type {current_type}; refusing to replace it."
        )

    drop_command = bq_global_args(config, "prettyjson")
    drop_command.extend(["query", "--use_legacy_sql=false"])
    run_process(
        drop_command,
        input_text=f"DROP {current_type} `{full_name}`;",
    )
    print(
        f"MIGRATED      {object_ref}: {current_type} -> {desired_type}"
    )


def model_paths() -> List[Path]:
    paths = sorted(MODEL_DIR.glob("*.sql")) + sorted(MART_DIR.glob("*.sql"))
    if not paths:
        raise RunnerError(
            f"No model SQL files found under {MODEL_DIR} or {MART_DIR}."
        )
    return paths


def qa_paths() -> List[Path]:
    paths = sorted(QA_DIR.glob("*.sql"))
    if not paths:
        raise RunnerError(f"No QA SQL files found under {QA_DIR}.")
    return paths


def analysis_paths() -> List[Path]:
    paths = sorted(ANALYSIS_DIR.glob("*.sql"))
    if not paths:
        raise RunnerError(f"No aggregate analysis SQL files found under {ANALYSIS_DIR}.")
    return paths


def setup_dataset(config: Dict[str, str]) -> None:
    dataset_ref = f"{config['project_id']}:{config['dataset_id']}"
    show_command = bq_global_args(config, "prettyjson")
    show_command.extend(["show", "--dataset", dataset_ref])
    shown = run_process(show_command, check=False)
    if shown.returncode == 0:
        print(f"Dataset ready: {dataset_ref}")
        return

    create_command = bq_global_args(config, "prettyjson")
    create_command.extend(
        [
            "mk",
            "--dataset",
            f"--location={config['location']}",
            "--description=Governed analytical views for Product Growth Analytics",
            dataset_ref,
        ]
    )
    run_process(create_command)
    print(f"Created dataset: {dataset_ref}")


def active_account_is_configured() -> bool:
    command = [
        find_tool("gcloud"),
        "auth",
        "list",
        "--filter=status:ACTIVE",
        "--format=value(account)",
    ]
    result = run_process(command, check=False)
    return result.returncode == 0 and bool(result.stdout.strip())


def command_auth(_: argparse.Namespace) -> None:
    command = [find_tool("gcloud"), "auth", "login", "--update-adc"]
    run_process(command, capture=False)
    print("Google Cloud user authentication and ADC are configured.")


def command_doctor(_: argparse.Namespace) -> None:
    config = require_config()
    bq_path = find_tool("bq")
    gcloud_path = find_tool("gcloud")
    if not active_account_is_configured():
        raise RunnerError("No active Google Cloud account. Run `make auth` once.")

    print(f"gcloud: {gcloud_path}")
    print(f"bq: {bq_path}")
    print("Authentication: active account configured")
    print(f"Project: {config['project_id']}")
    print(f"Dataset: {config['dataset_id']} ({config['location']})")
    print(f"Per-query byte ceiling: {int(config['max_bytes']):,}")


def selected_paths(
    requested: Sequence[str],
    default_paths: Iterable[Path],
) -> List[Path]:
    if not requested:
        return list(default_paths)
    paths = [Path(value).expanduser().resolve() for value in requested]
    for path in paths:
        if not path.is_file():
            raise RunnerError(f"SQL file not found: {path}")
    return paths


def command_dry_run(args: argparse.Namespace) -> None:
    config = require_config()
    paths = selected_paths(args.sql_files, model_paths())
    for path in paths:
        execute_sql(path, config, dry_run=True, output_format="prettyjson")
        print(f"DRY RUN PASS  {path.relative_to(ROOT)}")


def command_setup(_: argparse.Namespace) -> None:
    setup_dataset(require_config())


def command_build(args: argparse.Namespace) -> None:
    config = require_config()
    setup_dataset(config)
    paths = selected_paths(getattr(args, "sql_files", []), model_paths())
    for path in paths:
        migrate_model_object_type(path, config)
        execute_sql(path, config, dry_run=True, output_format="prettyjson")
        print(f"DRY RUN PASS  {path.relative_to(ROOT)}")
        execute_sql(path, config, output_format="prettyjson")
        print(f"BUILT         {path.relative_to(ROOT)}")


def write_result(run_dir: Path, path: Path, output: str) -> Path:
    run_dir.mkdir(parents=True, exist_ok=True)
    destination = run_dir / f"{path.stem}.csv"
    destination.write_text(output, encoding="utf-8")
    return destination


def qa_failures(csv_text: str) -> List[Dict[str, str]]:
    rows = list(csv.DictReader(csv_text.splitlines()))
    if not rows:
        raise RunnerError("QA query returned no rows.")
    if "status" not in rows[0]:
        raise RunnerError("QA output is missing the required `status` column.")
    return [row for row in rows if row.get("status") != "PASS"]


def command_qa(_: argparse.Namespace) -> None:
    config = require_config()
    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = RESULT_ROOT / timestamp
    all_failures: List[Dict[str, str]] = []

    for path in qa_paths():
        output = execute_sql(path, config, output_format="csv")
        destination = write_result(run_dir, path, output)
        failures = qa_failures(output)
        all_failures.extend(failures)
        print(
            f"QA {'PASS' if not failures else 'FAIL'}       "
            f"{path.relative_to(ROOT)} -> {destination.relative_to(ROOT)}"
        )

    if all_failures:
        for failure in all_failures:
            print(
                "FAILED CHECK  "
                f"{failure.get('check_name', '[unnamed]')}: "
                f"actual={failure.get('actual_value', '')}, "
                f"expected={failure.get('expected_value', '')}",
                file=sys.stderr,
            )
        raise RunnerError(f"{len(all_failures)} QA check(s) failed.")

    print(f"All QA checks passed. Results: {run_dir.relative_to(ROOT)}")


def command_extract(args: argparse.Namespace) -> None:
    config = require_config()
    paths = selected_paths(getattr(args, "sql_files", []), analysis_paths())
    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = RESULT_ROOT / timestamp

    for path in paths:
        output = execute_sql(path, config, output_format="csv")
        destination = write_result(run_dir, path, output)
        print(
            f"EXTRACTED     {path.relative_to(ROOT)} -> "
            f"{destination.relative_to(ROOT)}"
        )

    print(f"Aggregate analysis results: {run_dir.relative_to(ROOT)}")


def command_all(args: argparse.Namespace) -> None:
    command_doctor(args)
    command_build(args)
    command_qa(args)
    command_extract(args)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Automate BigQuery model builds and reconciliations."
    )
    parser.add_argument(
        "--env-file",
        type=Path,
        default=DEFAULT_ENV_FILE,
        help="Path to the local environment file (default: .env).",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    auth_parser = subparsers.add_parser(
        "auth",
        help="Complete the one-time browser login and configure ADC.",
    )
    auth_parser.set_defaults(func=command_auth)

    doctor_parser = subparsers.add_parser(
        "doctor",
        help="Check local tools, authentication, and project configuration.",
    )
    doctor_parser.set_defaults(func=command_doctor)

    setup_parser = subparsers.add_parser(
        "setup",
        help="Create the destination dataset when it does not exist.",
    )
    setup_parser.set_defaults(func=command_setup)

    dry_run_parser = subparsers.add_parser(
        "dry-run",
        help="Ask BigQuery to validate model SQL without building views.",
    )
    dry_run_parser.add_argument(
        "sql_files",
        nargs="*",
        help="Optional SQL paths; defaults to every model in execution order.",
    )
    dry_run_parser.set_defaults(func=command_dry_run)

    build_parser_command = subparsers.add_parser(
        "build",
        help="Create or replace governed core models and refreshed marts.",
    )
    build_parser_command.add_argument(
        "sql_files",
        nargs="*",
        help="Optional SQL paths; defaults to all core models and marts.",
    )
    build_parser_command.set_defaults(func=command_build)

    qa_parser = subparsers.add_parser(
        "qa",
        help="Run reconciliations and save aggregate CSV results locally.",
    )
    qa_parser.set_defaults(func=command_qa)

    extract_parser = subparsers.add_parser(
        "extract",
        help="Run aggregate analysis queries and save dashboard-safe CSV results.",
    )
    extract_parser.add_argument(
        "sql_files",
        nargs="*",
        help="Optional SQL paths; defaults to every aggregate analysis query.",
    )
    extract_parser.set_defaults(func=command_extract)

    all_parser = subparsers.add_parser(
        "all",
        help=(
            "Run doctor, build every model, require all QA checks to pass, "
            "and export aggregate results."
        ),
    )
    all_parser.set_defaults(func=command_all)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        load_env_file(args.env_file.expanduser().resolve())
        args.func(args)
        return 0
    except RunnerError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
