"""Offline unit tests for the standard-library helpers in scripts/bq_runner.py."""

from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from types import ModuleType
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]


def load_runner() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "bq_runner",
        ROOT / "scripts" / "bq_runner.py",
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


runner = load_runner()

CONFIG = {
    "project_id": "demo-project-123",
    "dataset_id": "product_growth_analytics",
    "location": "US",
    "max_bytes": "1000",
}


class ExtractCsvPayloadTest(unittest.TestCase):
    def test_strips_multi_statement_progress_text(self) -> None:
        output = (
            "CREATE TEMP TABLE eligible_sessions AS SELECT 1;\n"
            "Created temp table eligible_sessions\n"
            "diagnostic_section,metric_name,metric_rate\n"
            "coverage_by_dimension,purchase_after_checkout_rate,0.48\n"
            '"coverage_by_dimension","purchase_telemetry_gap_rate",0.38\n'
        )
        self.assertEqual(
            runner.extract_csv_payload(output),
            "diagnostic_section,metric_name,metric_rate\n"
            "coverage_by_dimension,purchase_after_checkout_rate,0.48\n"
            '"coverage_by_dimension","purchase_telemetry_gap_rate",0.38\n',
        )

    def test_returns_plain_csv_unchanged(self) -> None:
        output = "check_name,status\nstg_event_rows,PASS\n"
        self.assertEqual(runner.extract_csv_payload(output), output)

    def test_returns_unrecognized_output_unchanged(self) -> None:
        output = "No rows returned\n"
        self.assertEqual(runner.extract_csv_payload(output), output)


class RenderSqlTest(unittest.TestCase):
    def render(self, sql: str) -> str:
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "model.sql"
            path.write_text(sql, encoding="utf-8")
            return runner.render_sql(path, CONFIG)

    def test_substitutes_project_and_dataset(self) -> None:
        self.assertEqual(
            self.render("SELECT * FROM `{{ project_id }}.{{ dataset_id }}.t`"),
            "SELECT * FROM `demo-project-123.product_growth_analytics.t`",
        )

    def test_rejects_unresolved_placeholders(self) -> None:
        with self.assertRaisesRegex(runner.RunnerError, "unresolved"):
            self.render("SELECT '{{project_id}}', '{{ start_date }}'")


class LoadEnvFileTest(unittest.TestCase):
    def load(self, text: str) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / ".env"
            path.write_text(text, encoding="utf-8")
            runner.load_env_file(path)

    def test_parses_quotes_and_comments_without_overriding(self) -> None:
        with mock.patch.dict(os.environ, {"BQ_LOCATION": "EU"}, clear=True):
            self.load(
                "# comment\n"
                "\n"
                "BQ_PROJECT_ID='demo-project-123'\n"
                'BQ_DATASET_ID = "product_growth_analytics"\n'
                "BQ_LOCATION=US\n"
            )
            self.assertEqual(os.environ["BQ_PROJECT_ID"], "demo-project-123")
            self.assertEqual(
                os.environ["BQ_DATASET_ID"],
                "product_growth_analytics",
            )
            self.assertEqual(os.environ["BQ_LOCATION"], "EU")

    def test_rejects_lines_without_assignment(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(runner.RunnerError, "KEY=VALUE"):
                self.load("BQ_PROJECT_ID\n")

    def test_missing_file_is_ignored(self) -> None:
        runner.load_env_file(ROOT / "does-not-exist.env")


class RequireConfigTest(unittest.TestCase):
    def test_rejects_placeholder_project(self) -> None:
        environment = {
            "BQ_PROJECT_ID": "your-google-cloud-project-id",
            "BQ_DATASET_ID": "product_growth_analytics",
        }
        with mock.patch.dict(os.environ, environment, clear=True):
            with self.assertRaisesRegex(runner.RunnerError, "BQ_PROJECT_ID"):
                runner.require_config()

    def test_accepts_valid_configuration(self) -> None:
        environment = {
            "BQ_PROJECT_ID": "demo-project-123",
            "BQ_DATASET_ID": "product_growth_analytics",
        }
        with mock.patch.dict(os.environ, environment, clear=True):
            self.assertEqual(
                runner.require_config(),
                {
                    "project_id": "demo-project-123",
                    "dataset_id": "product_growth_analytics",
                    "location": "US",
                    "max_bytes": "10000000000",
                },
            )


class QaFailuresTest(unittest.TestCase):
    def test_returns_only_non_passing_rows(self) -> None:
        csv_text = (
            "check_name,status,actual_value,expected_value\n"
            "a,PASS,1,1\n"
            "b,FAIL,2,3\n"
        )
        self.assertEqual(
            [row["check_name"] for row in runner.qa_failures(csv_text)],
            ["b"],
        )

    def test_requires_rows_and_status_column(self) -> None:
        with self.assertRaisesRegex(runner.RunnerError, "no rows"):
            runner.qa_failures("check_name,status\n")
        with self.assertRaisesRegex(runner.RunnerError, "status"):
            runner.qa_failures("check_name\na\n")


if __name__ == "__main__":
    unittest.main()
