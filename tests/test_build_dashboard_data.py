"""Offline regression tests for scripts/build_dashboard_data.py.

The real inputs are BigQuery aggregate exports under the Git-ignored
data/interim/ directory. These tests rebuild the minimal input columns from
the committed dashboard extracts, run the builder in a temporary tree, and
require byte-identical outputs. No BigQuery access is needed.
"""

from __future__ import annotations

import csv
import filecmp
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import ModuleType


ROOT = Path(__file__).resolve().parents[1]
BUILDER_PATH = ROOT / "scripts" / "build_dashboard_data.py"
PUBLISHED_DIR = ROOT / "dashboard" / "aggregated_data"
SITE_DATA_PATH = ROOT / "dashboard" / "site" / "app" / "dashboard-data.json"
SITE_PUBLIC_DATA_DIR = ROOT / "dashboard" / "site" / "public" / "data"


def load_builder() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "build_dashboard_data",
        BUILDER_PATH,
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_published(file_name: str) -> list[dict[str, str]]:
    with (PUBLISHED_DIR / file_name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def write_rows(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def write_inputs(run_dir: Path, builder: ModuleType) -> None:
    """Recreate every required input from the committed aggregate extracts.

    Rows the builder must filter out are added on purpose, so the filters are
    exercised as well as the pass-through columns.
    """
    funnel = read_published("funnel_overall.csv")
    kpi = read_published("kpi_summary.csv")[0]
    kpi["checkout_completion_rate"] = funnel[-1]["step_conversion_rate"]
    write_rows(run_dir / "01_metric_tree_summary.csv", [kpi])
    write_rows(run_dir / "02_funnel_overall.csv", funnel)

    segments = read_published("segment_funnel.csv")
    segments.append(
        {**segments[0], "segment_type": "Country", "segment_value": "Excluded"}
    )
    segments.append(
        {**segments[0], "segment_value": "unreportable", "is_reportable": "false"}
    )
    write_rows(run_dir / "03_funnel_by_segment.csv", segments)

    pages = [
        {**row, "is_reportable": "true"}
        for row in read_published("page_opportunities.csv")
    ]
    pages.append({**pages[-1], "page_opportunity_rank": "11"})
    pages.append({**pages[0], "is_reportable": "false"})
    write_rows(run_dir / "04_page_opportunity.csv", pages)

    retention = []
    for row in read_published("retention_curve.csv"):
        for cohort_index in range(int(row["complete_cohorts"])):
            retention.append(
                {
                    "retention_week": row["retention_week"],
                    "cohort_users": row["cohort_users"] if cohort_index == 0 else "0",
                    "active_users": row["active_users"] if cohort_index == 0 else "0",
                    "is_complete_followup_cell": "true",
                }
            )
    retention.append(
        {
            "retention_week": "9",
            "cohort_users": "10",
            "active_users": "1",
            "is_complete_followup_cell": "false",
        }
    )
    write_rows(run_dir / "06_retention_weekly.csv", retention)

    daily = [
        {
            "metric_date": f"{row['month']}-01",
            "sessions": row["sessions"],
            "product_view_sessions": row["product_view_sessions"],
            "ordered_checkout_sessions": row["ordered_checkout_sessions"],
            "purchasing_sessions": row["purchasing_sessions"],
            "orders": row["orders"],
            "revenue_usd": row["revenue_usd"],
        }
        for row in read_published("monthly_performance.csv")
    ]
    write_rows(run_dir / "08_metric_tree_daily.csv", daily)

    specs = {spec[0]: spec for spec in builder.TELEMETRY_SPECS}
    diagnostic = []
    for row in read_published("checkout_telemetry_summary.csv"):
        _, _, section, dimension_type, dimension_value, metric_name, _ = specs[
            row["metric_key"]
        ]
        diagnostic.append(
            {
                "diagnostic_section": section,
                "dimension_type": dimension_type,
                "dimension_value": dimension_value,
                "metric_name": metric_name,
                "numerator_sessions": row["numerator_sessions"],
                "denominator_sessions": row["denominator_sessions"],
                "metric_rate": row["metric_rate"],
                "metric_rate_ci95_lower": "",
                "metric_rate_ci95_upper": "",
                "minimum_denominator": "",
                "is_reportable": "true",
                "reconciliation_status": row["reconciliation_status"],
            }
        )
    for row in read_published("checkout_telemetry_by_segment.csv"):
        diagnostic.append(
            {
                "diagnostic_section": "coverage_by_dimension",
                "dimension_type": row["segment_type"],
                "dimension_value": row["segment_value"],
                "metric_name": "purchase_telemetry_gap_rate",
                "numerator_sessions": row["gap_purchase_sessions"],
                "denominator_sessions": row["purchase_sessions"],
                "metric_rate": row["gap_rate"],
                "metric_rate_ci95_lower": row["gap_rate_ci95_lower"],
                "metric_rate_ci95_upper": row["gap_rate_ci95_upper"],
                "minimum_denominator": row["minimum_denominator"],
                "is_reportable": "true",
                "reconciliation_status": "PASS",
            }
        )
    write_rows(run_dir / "11_checkout_telemetry_diagnostic.csv", diagnostic)


class BuildDashboardDataTest(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.builder = load_builder()
        source_run = read_published("data_manifest.csv")[0]["source_run"]
        self.run_dir = (
            self.root / "data" / "interim" / "query_results" / source_run
        )
        write_inputs(self.run_dir, self.builder)

        self.builder.ROOT = self.root
        self.builder.RESULT_ROOT = self.run_dir.parent
        self.builder.OUTPUT_DIR = self.root / "dashboard" / "aggregated_data"
        self.builder.SITE_DATA_PATH = (
            self.root / "dashboard" / "site" / "app" / "dashboard-data.json"
        )
        self.builder.SITE_PUBLIC_DATA_DIR = (
            self.root / "dashboard" / "site" / "public" / "data"
        )

    def test_rebuilds_committed_outputs_byte_for_byte(self) -> None:
        self.builder.main()

        produced = sorted(
            path.name for path in self.builder.OUTPUT_DIR.glob("*.csv")
        )
        committed = sorted(path.name for path in PUBLISHED_DIR.glob("*.csv"))
        self.assertEqual(produced, committed)

        pairs = [(self.builder.SITE_DATA_PATH, SITE_DATA_PATH)]
        for name in committed:
            pairs.append((self.builder.OUTPUT_DIR / name, PUBLISHED_DIR / name))
            pairs.append(
                (
                    self.builder.SITE_PUBLIC_DATA_DIR / name,
                    SITE_PUBLIC_DATA_DIR / name,
                )
            )
        for produced_path, committed_path in pairs:
            with self.subTest(file=committed_path.relative_to(ROOT).as_posix()):
                self.assertTrue(
                    filecmp.cmp(produced_path, committed_path, shallow=False),
                    f"{produced_path.name} differs from the committed file",
                )

    def test_failed_reconciliation_writes_nothing(self) -> None:
        funnel_path = self.run_dir / "02_funnel_overall.csv"
        with funnel_path.open(encoding="utf-8", newline="") as handle:
            funnel = list(csv.DictReader(handle))
        funnel[-1]["sessions"] = str(int(funnel[-1]["sessions"]) - 1)
        write_rows(funnel_path, funnel)

        with self.assertRaisesRegex(
            self.builder.DashboardDataError,
            "Ordered funnel purchase count",
        ):
            self.builder.main()

        written = [
            path for path in (self.root / "dashboard").rglob("*") if path.is_file()
        ] if (self.root / "dashboard").exists() else []
        self.assertEqual(written, [])

    def test_mismatched_design_summary_writes_nothing(self) -> None:
        summary = json.loads(
            self.builder.DESIGN_SUMMARY_PATH.read_text(encoding="utf-8")
        )
        summary["primary_only"]["core_per_arm"] += 1
        stale_summary = self.root / "stale_summary.json"
        stale_summary.write_text(json.dumps(summary), encoding="utf-8")
        self.builder.DESIGN_SUMMARY_PATH = stale_summary

        with self.assertRaisesRegex(
            self.builder.DashboardDataError,
            "does not match the current aggregates",
        ):
            self.builder.main()
        self.assertFalse((self.root / "dashboard").exists())

    def test_sample_size_matches_planning_contract(self) -> None:
        baseline = 2_491 / 5_187
        self.assertEqual(self.builder.sample_size_per_arm(baseline, 0.05), 1_569)
        self.assertEqual(
            self.builder.sample_size_per_arm(baseline, 0.005),
            156_790,
        )

    def test_wilson_interval_brackets_the_rate(self) -> None:
        lower, upper = self.builder.wilson_interval(46, 3_830)
        self.assertAlmostEqual(lower, 0.009016753030629593, places=12)
        self.assertAlmostEqual(upper, 0.015982052958122835, places=12)
        self.assertEqual(self.builder.wilson_interval(0, 0), (0.0, 0.0))


class ExperimentDesignSummaryTest(unittest.TestCase):
    # The notebook asserts these properties when it runs; this guards the
    # committed summary that the dashboard and memo read.

    @classmethod
    def setUpClass(cls) -> None:
        path = ROOT / "notebooks" / "outputs" / "experiment_design_summary.json"
        cls.summary = json.loads(path.read_text(encoding="utf-8"))

    def test_plan_meets_its_operating_characteristics(self) -> None:
        plan = self.summary["plan"]
        self.assertGreaterEqual(plan["ship_probability_at_mde"], 0.80)
        self.assertLessEqual(plan["ship_probability_no_effect"], 0.025)
        self.assertLessEqual(plan["ship_probability_harmful_change"], 0.03)
        self.assertLess(
            self.summary["original_plan_audit"]["ship_probability_at_mde"],
            0.40,
        )
        self.assertEqual(
            plan["enrollment_total"], 2 * plan["enrollment_per_arm"]
        )
        self.assertGreaterEqual(plan["enrollment_per_arm"], plan["core_per_arm"])

    def test_boundaries_are_strict_early_and_end_near_196(self) -> None:
        bounds = [row["z_boundary"] for row in self.summary["boundaries"]]
        self.assertEqual(len(bounds), self.summary["assumptions"]["planned_looks"])
        self.assertEqual(bounds, sorted(bounds, reverse=True))
        self.assertAlmostEqual(bounds[-1], 2.024, places=2)

    def test_example_is_labeled_simulated(self) -> None:
        example = self.summary["simulated_example"]
        self.assertIs(example["is_simulated"], True)
        self.assertEqual(example["evidence_value"], "demonstration_only")


if __name__ == "__main__":
    unittest.main()
