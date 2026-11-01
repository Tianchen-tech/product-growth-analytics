#!/usr/bin/env python3
"""Build privacy-safe dashboard extracts from the latest complete query run.

The script uses only the Python standard library. It deliberately publishes
aggregate rows only: no user, session, event, order, or transaction identifiers
are copied into the dashboard folder.
"""

from __future__ import annotations

import csv
import hashlib
import json
import shutil
from collections import defaultdict
from math import ceil, sqrt
from pathlib import Path
from statistics import NormalDist
from typing import Iterable, Mapping, Sequence


ROOT = Path(__file__).resolve().parents[1]
RESULT_ROOT = ROOT / "data" / "interim" / "query_results"
OUTPUT_DIR = ROOT / "dashboard" / "aggregated_data"
SITE_DATA_PATH = ROOT / "dashboard" / "site" / "app" / "dashboard-data.json"
SITE_PUBLIC_DATA_DIR = ROOT / "dashboard" / "site" / "public" / "data"

REQUIRED_INPUTS = {
    "metric_tree": "01_metric_tree_summary.csv",
    "funnel": "02_funnel_overall.csv",
    "segments": "03_funnel_by_segment.csv",
    "pages": "04_page_opportunity.csv",
    "retention": "06_retention_weekly.csv",
    "daily": "08_metric_tree_daily.csv",
    "checkout_diagnostic": "11_checkout_telemetry_diagnostic.csv",
}

ALPHA = 0.05
TARGET_POWER = 0.80
PLANNED_MDE = 0.05
OPERATIONAL_BUFFER = 0.05
SIMULATION_SEED = 20260731
POWER_SIMULATION_SEED = 20260801

# Checkout telemetry metrics published to the dashboard:
# (metric_key, label, diagnostic_section, dimension_type, dimension_value,
#  metric_name, interpretation).
TELEMETRY_SPECS = [
    (
        "checkout_purchase_rate",
        "Purchases after checkout",
        "coverage_by_dimension",
        "Overall",
        "All checkout sessions",
        "purchase_after_checkout_rate",
        "Observed historical behavior",
    ),
    (
        "strict_sequence_purchase_rate",
        "Strict shipping → payment → purchase",
        "coverage_by_dimension",
        "Overall",
        "All checkout sessions",
        "strict_sequence_purchase_rate_of_checkout",
        "Sequence-dependent diagnostic",
    ),
    (
        "strict_coverage_of_purchases",
        "Purchases with the strict intermediate sequence",
        "coverage_by_dimension",
        "Overall",
        "All checkout sessions",
        "strict_intermediate_coverage_rate_of_purchases",
        "Sequence-dependent diagnostic",
    ),
    (
        "purchase_sequence_gap",
        "Purchases missing the strict intermediate sequence",
        "coverage_by_dimension",
        "Overall",
        "All checkout sessions",
        "purchase_telemetry_gap_rate",
        "Sequence/re-entry artifact; not abandonment",
    ),
    (
        "repeated_checkout_start",
        "Checkout sessions with repeated begin_checkout",
        "timing_and_duplication_flags",
        "Overall",
        "All checkout sessions",
        "multiple_begin_checkout_events",
        "Observed historical behavior",
    ),
    (
        "gap_shipping_before_checkout",
        "Gap purchases with shipping at/before governed checkout",
        "timing_and_duplication_flags",
        "Purchase telemetry gap",
        "Purchases missing the full intermediate sequence",
        "gap_has_shipping_at_or_before_checkout",
        "Supports sequence/re-entry diagnosis",
    ),
    (
        "gap_payment_before_purchase",
        "Gap purchases with payment before purchase",
        "timing_and_duplication_flags",
        "Purchase telemetry gap",
        "Purchases missing the full intermediate sequence",
        "gap_has_payment_before_purchase",
        "Supports sequence/re-entry diagnosis",
    ),
    (
        "gap_no_shipping_anywhere",
        "Gap purchases with no shipping event anywhere",
        "timing_and_duplication_flags",
        "Purchase telemetry gap",
        "Purchases missing the full intermediate sequence",
        "gap_has_no_shipping_event_anywhere",
        "Rules out broad missing-shipping telemetry",
    ),
]


class DashboardDataError(RuntimeError):
    """Raised when dashboard inputs are incomplete or inconsistent."""


def latest_complete_run() -> Path:
    if not RESULT_ROOT.exists():
        raise DashboardDataError(
            "No aggregate query results found. Run `make extract` first."
        )

    for candidate in sorted(RESULT_ROOT.iterdir(), reverse=True):
        if not candidate.is_dir():
            continue
        if all((candidate / name).is_file() for name in REQUIRED_INPUTS.values()):
            return candidate

    raise DashboardDataError(
        "No complete aggregate run contains every required dashboard input."
    )


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def as_int(value: str) -> int:
    return int(float(value))


def as_float(value: str) -> float:
    return float(value)


def as_bool(value: str) -> bool:
    return value.strip().lower() == "true"


def rounded(value: float, digits: int = 10) -> float:
    return round(value, digits)


def select_fields(
    row: Mapping[str, str],
    fields: Sequence[str],
) -> dict[str, str]:
    missing = [field for field in fields if field not in row]
    if missing:
        raise DashboardDataError(
            f"Missing expected columns: {', '.join(missing)}"
        )
    return {field: row[field] for field in fields}


def write_csv(
    path: Path,
    rows: Iterable[Mapping[str, object]],
    fields: Sequence[str],
) -> None:
    rows = list(rows)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=list(fields),
            extrasaction="raise",
        )
        writer.writeheader()
        writer.writerows(rows)


def wilson_interval(
    successes: int,
    total: int,
    alpha: float = ALPHA,
) -> tuple[float, float]:
    if total <= 0:
        return 0.0, 0.0
    z_value = NormalDist().inv_cdf(1 - alpha / 2)
    rate = successes / total
    denominator = 1 + z_value**2 / total
    center = (rate + z_value**2 / (2 * total)) / denominator
    margin = (
        z_value
        * sqrt(
            rate * (1 - rate) / total
            + z_value**2 / (4 * total**2)
        )
        / denominator
    )
    return center - margin, center + margin


def sample_size_per_arm(
    baseline: float,
    absolute_mde: float,
    alpha: float = ALPHA,
    power: float = TARGET_POWER,
) -> int:
    treatment = baseline + absolute_mde
    if not 0 < baseline < 1 or not 0 < treatment < 1:
        raise DashboardDataError(
            "Baseline and treatment rates must both be between zero and one."
        )

    z_alpha = NormalDist().inv_cdf(1 - alpha / 2)
    z_power = NormalDist().inv_cdf(power)
    pooled_midpoint = (baseline + treatment) / 2
    numerator = (
        z_alpha * sqrt(2 * pooled_midpoint * (1 - pooled_midpoint))
        + z_power
        * sqrt(
            baseline * (1 - baseline)
            + treatment * (1 - treatment)
        )
    ) ** 2
    return ceil(numerator / absolute_mde**2)


def diagnostic_row(
    rows: Sequence[Mapping[str, str]],
    *,
    section: str,
    dimension_type: str,
    dimension_value: str,
    metric_name: str,
) -> Mapping[str, str]:
    matches = [
        row
        for row in rows
        if row["diagnostic_section"] == section
        and row["dimension_type"] == dimension_type
        and row["dimension_value"] == dimension_value
        and row["metric_name"] == metric_name
    ]
    if len(matches) != 1:
        raise DashboardDataError(
            "Expected exactly one checkout diagnostic row for "
            f"{section}/{dimension_type}/{dimension_value}/{metric_name}; "
            f"found {len(matches)}."
        )
    return matches[0]


def main() -> None:
    source_run = latest_complete_run()
    inputs = {
        key: read_csv(source_run / filename)
        for key, filename in REQUIRED_INPUTS.items()
    }

    if len(inputs["metric_tree"]) != 1:
        raise DashboardDataError(
            "Metric-tree summary must contain exactly one row."
        )
    metric = inputs["metric_tree"][0]

    # Outputs are staged in memory and written only after every extract and
    # reconciliation guard has succeeded, so a failed run never leaves
    # partially refreshed or unreconciled dashboard data behind.
    staged_csvs: list[
        tuple[str, Sequence[Mapping[str, object]], Sequence[str]]
    ] = []

    kpi_fields = [
        "analysis_start_date",
        "analysis_end_date",
        "observed_calendar_days",
        "pseudonymous_users",
        "sessions",
        "engaged_sessions",
        "product_view_sessions",
        "ordered_checkout_sessions",
        "purchasing_sessions",
        "orders",
        "revenue_usd",
        "session_engagement_rate",
        "purchase_session_conversion_rate",
        "average_order_value_usd",
        "revenue_per_session_usd",
    ]
    kpi_row = select_fields(metric, kpi_fields)
    staged_csvs.append(("kpi_summary.csv", [kpi_row], kpi_fields))

    funnel_fields = [
        "stage_index",
        "stage_name",
        "sessions",
        "prior_stage_sessions",
        "step_conversion_rate",
        "cumulative_conversion_rate",
        "lost_sessions_from_prior_stage",
        "step_dropoff_rate",
    ]
    funnel_rows = [
        select_fields(row, funnel_fields)
        for row in sorted(
            inputs["funnel"],
            key=lambda row: as_int(row["stage_index"]),
        )
    ]
    staged_csvs.append(("funnel_overall.csv", funnel_rows, funnel_fields))

    segment_fields = [
        "segment_type",
        "segment_value",
        "metric_index",
        "metric_name",
        "sessions",
        "numerator_sessions",
        "denominator_sessions",
        "conversion_rate",
        "conversion_rate_ci95_lower",
        "conversion_rate_ci95_upper",
        "minimum_denominator",
        "is_reportable",
    ]
    segment_rows = [
        select_fields(row, segment_fields)
        for row in inputs["segments"]
        if row["segment_type"] in {"Device", "User tenure"}
        and as_bool(row["is_reportable"])
    ]
    segment_rows.sort(
        key=lambda row: (
            row["segment_type"],
            as_int(row["metric_index"]),
            row["segment_value"],
        )
    )
    staged_csvs.append(("segment_funnel.csv", segment_rows, segment_fields))

    page_fields = [
        "page_opportunity_rank",
        "canonical_page_title",
        "view_sessions",
        "attributed_add_sessions",
        "view_to_add_rate",
        "view_to_add_rate_ci95_lower",
        "view_to_add_rate_ci95_upper",
        "benchmark_view_to_add_rate",
        "scenario_incremental_add_sessions",
        "scenario_incremental_orders",
        "scenario_revenue_opportunity_usd",
        "opportunity_values_are_additive",
    ]
    page_rows = [
        select_fields(row, page_fields)
        for row in inputs["pages"]
        if as_bool(row["is_reportable"])
        and as_int(row["page_opportunity_rank"]) <= 10
    ]
    page_rows.sort(key=lambda row: as_int(row["page_opportunity_rank"]))
    if not page_rows:
        raise DashboardDataError("No reportable page opportunities were found.")
    staged_csvs.append(("page_opportunities.csv", page_rows, page_fields))

    retention_by_week: dict[int, dict[str, int]] = defaultdict(
        lambda: {"cohort_users": 0, "active_users": 0, "complete_cohorts": 0}
    )
    for row in inputs["retention"]:
        if not as_bool(row["is_complete_followup_cell"]):
            continue
        week = as_int(row["retention_week"])
        retention_by_week[week]["cohort_users"] += as_int(row["cohort_users"])
        retention_by_week[week]["active_users"] += as_int(row["active_users"])
        retention_by_week[week]["complete_cohorts"] += 1

    retention_rows: list[dict[str, object]] = []
    for week, values in sorted(retention_by_week.items()):
        cohort_users = values["cohort_users"]
        active_users = values["active_users"]
        lower, upper = wilson_interval(active_users, cohort_users)
        retention_rows.append(
            {
                "retention_week": week,
                "cohort_users": cohort_users,
                "active_users": active_users,
                "retention_rate": rounded(active_users / cohort_users),
                "retention_rate_ci95_lower": rounded(lower),
                "retention_rate_ci95_upper": rounded(upper),
                "complete_cohorts": values["complete_cohorts"],
            }
        )
    retention_fields = [
        "retention_week",
        "cohort_users",
        "active_users",
        "retention_rate",
        "retention_rate_ci95_lower",
        "retention_rate_ci95_upper",
        "complete_cohorts",
    ]
    staged_csvs.append(
        ("retention_curve.csv", retention_rows, retention_fields)
    )

    monthly: dict[str, dict[str, float]] = defaultdict(
        lambda: {
            "sessions": 0,
            "product_view_sessions": 0,
            "ordered_checkout_sessions": 0,
            "purchasing_sessions": 0,
            "orders": 0,
            "revenue_usd": 0.0,
        }
    )
    for row in inputs["daily"]:
        month = row["metric_date"][:7]
        for field in [
            "sessions",
            "product_view_sessions",
            "ordered_checkout_sessions",
            "purchasing_sessions",
            "orders",
        ]:
            monthly[month][field] += as_int(row[field])
        monthly[month]["revenue_usd"] += as_float(row["revenue_usd"])

    monthly_rows: list[dict[str, object]] = []
    for month, values in sorted(monthly.items()):
        sessions = int(values["sessions"])
        orders = int(values["orders"])
        monthly_rows.append(
            {
                "month": month,
                "sessions": sessions,
                "product_view_sessions": int(values["product_view_sessions"]),
                "ordered_checkout_sessions": int(
                    values["ordered_checkout_sessions"]
                ),
                "purchasing_sessions": int(values["purchasing_sessions"]),
                "orders": orders,
                "revenue_usd": rounded(values["revenue_usd"], 2),
                "purchase_session_conversion_rate": rounded(
                    values["purchasing_sessions"] / sessions
                ),
                "average_order_value_usd": rounded(
                    values["revenue_usd"] / orders if orders else 0.0,
                    2,
                ),
            }
        )
    monthly_fields = [
        "month",
        "sessions",
        "product_view_sessions",
        "ordered_checkout_sessions",
        "purchasing_sessions",
        "orders",
        "revenue_usd",
        "purchase_session_conversion_rate",
        "average_order_value_usd",
    ]
    staged_csvs.append(
        ("monthly_performance.csv", monthly_rows, monthly_fields)
    )

    checkout_sessions = as_int(metric["ordered_checkout_sessions"])
    average_order_value = as_float(metric["average_order_value_usd"])
    lift_rows = []
    for lift_pp in [0.25, 0.50, 1.00, 2.00, 3.00, 5.00]:
        absolute_lift = lift_pp / 100
        incremental_orders = checkout_sessions * absolute_lift
        lift_rows.append(
            {
                "absolute_lift_pp": lift_pp,
                "eligible_checkout_sessions": checkout_sessions,
                "scenario_incremental_orders": rounded(
                    incremental_orders,
                    4,
                ),
                "scenario_incremental_revenue_usd": rounded(
                    incremental_orders * average_order_value,
                    2,
                ),
                "evidence_type": "scenario_not_forecast",
            }
        )
    lift_fields = [
        "absolute_lift_pp",
        "eligible_checkout_sessions",
        "scenario_incremental_orders",
        "scenario_incremental_revenue_usd",
        "evidence_type",
    ]
    staged_csvs.append(("checkout_lift_scenarios.csv", lift_rows, lift_fields))

    diagnostic_rows = inputs["checkout_diagnostic"]
    telemetry_rows = []
    for (
        key,
        label,
        section,
        dimension_type,
        dimension_value,
        metric_name,
        interpretation,
    ) in TELEMETRY_SPECS:
        row = diagnostic_row(
            diagnostic_rows,
            section=section,
            dimension_type=dimension_type,
            dimension_value=dimension_value,
            metric_name=metric_name,
        )
        telemetry_rows.append(
            {
                "metric_key": key,
                "label": label,
                "numerator_sessions": as_int(row["numerator_sessions"]),
                "denominator_sessions": as_int(row["denominator_sessions"]),
                "metric_rate": rounded(as_float(row["metric_rate"])),
                "interpretation": interpretation,
                "reconciliation_status": row["reconciliation_status"],
            }
        )
    telemetry_fields = [
        "metric_key",
        "label",
        "numerator_sessions",
        "denominator_sessions",
        "metric_rate",
        "interpretation",
        "reconciliation_status",
    ]
    staged_csvs.append(
        ("checkout_telemetry_summary.csv", telemetry_rows, telemetry_fields)
    )

    telemetry_segment_rows = []
    for row in diagnostic_rows:
        if (
            row["diagnostic_section"] == "coverage_by_dimension"
            and row["dimension_type"] in {"Device", "User tenure"}
            and row["metric_name"] == "purchase_telemetry_gap_rate"
            and as_bool(row["is_reportable"])
        ):
            telemetry_segment_rows.append(
                {
                    "segment_type": row["dimension_type"],
                    "segment_value": row["dimension_value"],
                    "gap_purchase_sessions": as_int(row["numerator_sessions"]),
                    "purchase_sessions": as_int(row["denominator_sessions"]),
                    "gap_rate": rounded(as_float(row["metric_rate"])),
                    "gap_rate_ci95_lower": rounded(
                        as_float(row["metric_rate_ci95_lower"])
                    ),
                    "gap_rate_ci95_upper": rounded(
                        as_float(row["metric_rate_ci95_upper"])
                    ),
                    "minimum_denominator": as_int(
                        row["minimum_denominator"]
                    ),
                    "is_reportable": True,
                }
            )
    telemetry_segment_rows.sort(
        key=lambda row: (row["segment_type"], row["segment_value"])
    )
    telemetry_segment_fields = [
        "segment_type",
        "segment_value",
        "gap_purchase_sessions",
        "purchase_sessions",
        "gap_rate",
        "gap_rate_ci95_lower",
        "gap_rate_ci95_upper",
        "minimum_denominator",
        "is_reportable",
    ]
    staged_csvs.append(
        (
            "checkout_telemetry_by_segment.csv",
            telemetry_segment_rows,
            telemetry_segment_fields,
        )
    )

    baseline = as_float(metric["checkout_completion_rate"])
    observed_days = as_int(metric["observed_calendar_days"])
    daily_checkout_proxy = checkout_sessions / observed_days
    mde_rows = []
    for absolute_mde in [0.005, 0.01, 0.02, 0.03, 0.04, 0.05]:
        per_arm = sample_size_per_arm(baseline, absolute_mde)
        total = 2 * per_arm
        mde_rows.append(
            {
                "absolute_mde_pp": rounded(absolute_mde * 100, 2),
                "relative_lift": rounded(absolute_mde / baseline),
                "required_per_arm": per_arm,
                "required_total": total,
                "historical_volume_proxy_weeks": rounded(
                    total / daily_checkout_proxy / 7,
                    2,
                ),
            }
        )
    mde_fields = [
        "absolute_mde_pp",
        "relative_lift",
        "required_per_arm",
        "required_total",
        "historical_volume_proxy_weeks",
    ]
    staged_csvs.append(("mde_sensitivity.csv", mde_rows, mde_fields))

    core_per_arm = sample_size_per_arm(baseline, PLANNED_MDE)
    buffered_per_arm = ceil(core_per_arm * (1 + OPERATIONAL_BUFFER))
    buffered_total = 2 * buffered_per_arm
    experiment_row = {
        "historical_baseline_proxy": rounded(baseline),
        "alpha": ALPHA,
        "target_power": TARGET_POWER,
        "planned_absolute_mde_pp": PLANNED_MDE * 100,
        "core_sample_per_arm": core_per_arm,
        "core_total_sample": core_per_arm * 2,
        "operational_buffer": OPERATIONAL_BUFFER,
        "buffered_target_per_arm": buffered_per_arm,
        "buffered_total_target": buffered_total,
        "historical_checkout_session_proxy_per_day": rounded(
            daily_checkout_proxy,
            4,
        ),
        "historical_volume_proxy_weeks": rounded(
            buffered_total / daily_checkout_proxy / 7,
            2,
        ),
        "randomization_unit": "user",
        "exposure_rule": "sticky experiment_exposure; never re-randomize",
        "readiness_status": "design_ready_instrumentation_pending",
    }
    experiment_fields = list(experiment_row)
    staged_csvs.append(
        ("experiment_plan.csv", [experiment_row], experiment_fields)
    )

    simulation_row = {
        "is_simulated": True,
        "seed": SIMULATION_SEED,
        "control_conversion_rate": 0.4818,
        "treatment_conversion_rate": 0.5497,
        "estimated_difference_pp": 6.80,
        "ci95_lower_pp": 3.39,
        "ci95_upper_pp": 10.19,
        "two_sided_p_value": 0.00009,
        "srm_p_value": 0.2802,
        "revenue_per_eligible_user_difference_usd": 4.80,
        "payment_error_difference_pp": -0.03,
        "power_simulation_seed": POWER_SIMULATION_SEED,
        "aa_false_positive_rate": 0.0498,
        "ab_power_at_planned_mde": 0.8046,
        "evidence_value": "demonstration_only",
    }
    simulation_fields = list(simulation_row)
    staged_csvs.append(
        ("simulation_only_result.csv", [simulation_row], simulation_fields)
    )

    dashboard_data = {
        "metadata": {
            "sourceRun": source_run.name,
            "analysisStartDate": metric["analysis_start_date"],
            "analysisEndDate": metric["analysis_end_date"],
            "observedCalendarDays": observed_days,
            "dataLabel": "Historical GA4 sample; not current store performance",
            "privacy": "Aggregate-only; no user or session rows",
        },
        "kpis": {
            "users": as_int(metric["pseudonymous_users"]),
            "sessions": as_int(metric["sessions"]),
            "engagedSessions": as_int(metric["engaged_sessions"]),
            "productViewSessions": as_int(metric["product_view_sessions"]),
            "checkoutSessions": checkout_sessions,
            "purchasingSessions": as_int(metric["purchasing_sessions"]),
            "orders": as_int(metric["orders"]),
            "revenueUsd": rounded(as_float(metric["revenue_usd"]), 2),
            "engagementRate": rounded(
                as_float(metric["session_engagement_rate"])
            ),
            "purchaseSessionRate": rounded(
                as_float(metric["purchase_session_conversion_rate"])
            ),
            "averageOrderValueUsd": rounded(average_order_value, 2),
            "revenuePerSessionUsd": rounded(
                as_float(metric["revenue_per_session_usd"]),
                2,
            ),
        },
        "monthly": [
            {
                "month": row["month"],
                "sessions": row["sessions"],
                "orders": row["orders"],
                "revenueUsd": row["revenue_usd"],
                "purchaseSessionRate": row[
                    "purchase_session_conversion_rate"
                ],
                "averageOrderValueUsd": row["average_order_value_usd"],
            }
            for row in monthly_rows
        ],
        "funnel": [
            {
                "stageIndex": as_int(row["stage_index"]),
                "stageName": row["stage_name"],
                "sessions": as_int(row["sessions"]),
                "stepConversionRate": as_float(row["step_conversion_rate"]),
                "cumulativeConversionRate": as_float(
                    row["cumulative_conversion_rate"]
                ),
                "lostSessions": as_int(row["lost_sessions_from_prior_stage"]),
                "stepDropoffRate": as_float(row["step_dropoff_rate"]),
            }
            for row in funnel_rows
        ],
        "segments": [
            {
                "segmentType": row["segment_type"],
                "segmentValue": row["segment_value"],
                "metricIndex": as_int(row["metric_index"]),
                "metricName": row["metric_name"],
                "sessions": as_int(row["sessions"]),
                "numeratorSessions": as_int(row["numerator_sessions"]),
                "denominatorSessions": as_int(row["denominator_sessions"]),
                "conversionRate": as_float(row["conversion_rate"]),
                "ci95Lower": as_float(row["conversion_rate_ci95_lower"]),
                "ci95Upper": as_float(row["conversion_rate_ci95_upper"]),
            }
            for row in segment_rows
        ],
        "pageOpportunities": [
            {
                "rank": as_int(row["page_opportunity_rank"]),
                "title": row["canonical_page_title"],
                "viewSessions": as_int(row["view_sessions"]),
                "addSessions": as_int(row["attributed_add_sessions"]),
                "viewToAddRate": as_float(row["view_to_add_rate"]),
                "benchmarkRate": as_float(
                    row["benchmark_view_to_add_rate"]
                ),
                "scenarioIncrementalOrders": as_float(
                    row["scenario_incremental_orders"]
                ),
                "scenarioRevenueUsd": as_float(
                    row["scenario_revenue_opportunity_usd"]
                ),
            }
            for row in page_rows
        ],
        "retention": [
            {
                "week": row["retention_week"],
                "cohortUsers": row["cohort_users"],
                "activeUsers": row["active_users"],
                "rate": row["retention_rate"],
                "ci95Lower": row["retention_rate_ci95_lower"],
                "ci95Upper": row["retention_rate_ci95_upper"],
                "completeCohorts": row["complete_cohorts"],
            }
            for row in retention_rows
        ],
        "checkoutTelemetry": [
            {
                "key": row["metric_key"],
                "label": row["label"],
                "numeratorSessions": row["numerator_sessions"],
                "denominatorSessions": row["denominator_sessions"],
                "rate": row["metric_rate"],
                "interpretation": row["interpretation"],
            }
            for row in telemetry_rows
        ],
        "telemetrySegments": [
            {
                "segmentType": row["segment_type"],
                "segmentValue": row["segment_value"],
                "gapSessions": row["gap_purchase_sessions"],
                "purchaseSessions": row["purchase_sessions"],
                "gapRate": row["gap_rate"],
                "ci95Lower": row["gap_rate_ci95_lower"],
                "ci95Upper": row["gap_rate_ci95_upper"],
            }
            for row in telemetry_segment_rows
        ],
        "checkoutLiftScenarios": [
            {
                "absoluteLiftPp": row["absolute_lift_pp"],
                "eligibleCheckoutSessions": row[
                    "eligible_checkout_sessions"
                ],
                "incrementalOrders": row["scenario_incremental_orders"],
                "incrementalRevenueUsd": row[
                    "scenario_incremental_revenue_usd"
                ],
            }
            for row in lift_rows
        ],
        "experimentPlan": {
            "historicalBaselineProxy": experiment_row[
                "historical_baseline_proxy"
            ],
            "alpha": experiment_row["alpha"],
            "targetPower": experiment_row["target_power"],
            "plannedMdePp": experiment_row["planned_absolute_mde_pp"],
            "coreSamplePerArm": experiment_row["core_sample_per_arm"],
            "bufferedTargetPerArm": experiment_row[
                "buffered_target_per_arm"
            ],
            "bufferedTotal": experiment_row["buffered_total_target"],
            "proxyUnitsPerDay": experiment_row[
                "historical_checkout_session_proxy_per_day"
            ],
            "proxyWeeks": experiment_row[
                "historical_volume_proxy_weeks"
            ],
            "randomizationUnit": experiment_row["randomization_unit"],
            "exposureRule": experiment_row["exposure_rule"],
            "readinessStatus": experiment_row["readiness_status"],
        },
        "mdeSensitivity": [
            {
                "absoluteMdePp": row["absolute_mde_pp"],
                "relativeLift": row["relative_lift"],
                "requiredPerArm": row["required_per_arm"],
                "requiredTotal": row["required_total"],
                "proxyWeeks": row["historical_volume_proxy_weeks"],
            }
            for row in mde_rows
        ],
        "simulationOnly": {
            "isSimulated": simulation_row["is_simulated"],
            "seed": simulation_row["seed"],
            "controlRate": simulation_row["control_conversion_rate"],
            "treatmentRate": simulation_row["treatment_conversion_rate"],
            "differencePp": simulation_row["estimated_difference_pp"],
            "ci95LowerPp": simulation_row["ci95_lower_pp"],
            "ci95UpperPp": simulation_row["ci95_upper_pp"],
            "pValue": simulation_row["two_sided_p_value"],
            "srmPValue": simulation_row["srm_p_value"],
            "falsePositiveRate": simulation_row["aa_false_positive_rate"],
            "power": simulation_row["ab_power_at_planned_mde"],
            "evidenceValue": simulation_row["evidence_value"],
        },
    }

    telemetry_by_key = {row["metric_key"]: row for row in telemetry_rows}
    if core_per_arm != 1_569 or buffered_per_arm != 1_648:
        raise DashboardDataError(
            "Experiment sample-size reconciliation changed unexpectedly."
        )
    if as_int(funnel_rows[-1]["sessions"]) != 2_491:
        raise DashboardDataError(
            "Ordered funnel purchase count changed unexpectedly."
        )
    if telemetry_by_key["purchase_sequence_gap"]["numerator_sessions"] != 941:
        raise DashboardDataError(
            "Checkout telemetry-gap reconciliation changed unexpectedly."
        )

    for file_name, rows, fields in staged_csvs:
        write_csv(OUTPUT_DIR / file_name, rows, fields)
    SITE_DATA_PATH.parent.mkdir(parents=True, exist_ok=True)
    SITE_DATA_PATH.write_text(
        json.dumps(
            dashboard_data,
            ensure_ascii=False,
            indent=2,
            sort_keys=False,
        )
        + "\n",
        encoding="utf-8",
    )

    manifest_files = sorted(
        OUTPUT_DIR / file_name for file_name, _, _ in staged_csvs
    )
    manifest_rows = []
    for path in manifest_files:
        row_count = max(
            0,
            len(path.read_text(encoding="utf-8").splitlines()) - 1,
        )
        manifest_rows.append(
            {
                "file_name": path.name,
                "row_count": row_count,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "source_run": source_run.name,
                "privacy_level": "aggregate_only",
            }
        )
    manifest_fields = [
        "file_name",
        "row_count",
        "sha256",
        "source_run",
        "privacy_level",
    ]
    write_csv(
        OUTPUT_DIR / "data_manifest.csv",
        manifest_rows,
        manifest_fields,
    )
    SITE_PUBLIC_DATA_DIR.mkdir(parents=True, exist_ok=True)
    for path in [*manifest_files, OUTPUT_DIR / "data_manifest.csv"]:
        shutil.copy2(path, SITE_PUBLIC_DATA_DIR / path.name)

    print(f"Dashboard data built from {source_run.name}")
    print(f"Aggregate CSVs: {len(manifest_rows)}")
    print(f"Site data: {SITE_DATA_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    try:
        main()
    except DashboardDataError as error:
        raise SystemExit(f"Dashboard data error: {error}") from error
