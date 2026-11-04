"use client";

import {
  ArrowDownRight,
  ArrowRight,
  BarChart3,
  CheckCircle2,
  CircleDollarSign,
  Database,
  Download,
  FlaskConical,
  Gauge,
  Info,
  Layers3,
  PackageSearch,
  ShieldCheck,
  ShoppingCart,
  Target,
  TrendingUp,
  UsersRound,
} from "lucide-react";
import { useMemo, useState, type CSSProperties } from "react";
import data from "./dashboard-data.json";


type FunnelMode = "step" | "cumulative";
type SegmentType = "Device" | "User tenure";
type SegmentMetric =
  | "purchase_session_conversion"
  | "view_to_cart"
  | "checkout_to_purchase";

const numberFormat = new Intl.NumberFormat("en-US");
const compactNumberFormat = new Intl.NumberFormat("en-US", {
  notation: "compact",
  maximumFractionDigits: 1,
});
const currencyFormat = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  maximumFractionDigits: 0,
});

const monthFormat = new Intl.DateTimeFormat("en-US", {
  month: "short",
  year: "numeric",
  timeZone: "UTC",
});

const stageLabels: Record<string, string> = {
  view_item: "View item",
  add_to_cart: "Add to cart",
  begin_checkout: "Begin checkout",
  purchase: "Purchase",
};

const metricOptions: Array<{
  value: SegmentMetric;
  label: string;
}> = [
  {
    value: "purchase_session_conversion",
    label: "Purchase / session",
  },
  {
    value: "view_to_cart",
    label: "View → cart",
  },
  {
    value: "checkout_to_purchase",
    label: "Checkout → purchase",
  },
];

function formatPercent(value: number, digits = 2): string {
  return `${(value * 100).toFixed(digits)}%`;
}

function formatSigned(value: number, digits = 2): string {
  const sign = value > 0 ? "+" : "";
  return `${sign}${value.toFixed(digits)}`;
}

function formatPp(value: number, digits = 2): string {
  return `${formatSigned(value, digits)} pp`;
}

function formatMonth(isoDateOrMonth: string): string {
  const [year, month] = isoDateOrMonth.split("-").map(Number);
  if (!year || !month) {
    return isoDateOrMonth;
  }
  return monthFormat.format(new Date(Date.UTC(year, month - 1, 1)));
}

function barStyle(width: number): CSSProperties {
  return {
    "--bar-width": `${Math.max(0, Math.min(width, 100))}%`,
  } as CSSProperties;
}

function telemetryMetric(key: string) {
  const metric = data.checkoutTelemetry.find((item) => item.key === key);
  if (!metric) {
    throw new Error(`Missing checkout telemetry metric: ${key}`);
  }
  return metric;
}

function funnelStage(stageName: string) {
  const stage = data.funnel.find((item) => item.stageName === stageName);
  if (!stage) {
    throw new Error(`Missing funnel stage: ${stageName}`);
  }
  return stage;
}

const checkoutPurchase = telemetryMetric("checkout_purchase_rate");
const strictCoverage = telemetryMetric("strict_coverage_of_purchases");
const sequenceGap = telemetryMetric("purchase_sequence_gap");
const repeatedCheckout = telemetryMetric("repeated_checkout_start");
const gapShippingBefore = telemetryMetric("gap_shipping_before_checkout");
const gapPaymentBefore = telemetryMetric("gap_payment_before_purchase");
const gapNoShipping = telemetryMetric("gap_no_shipping_anywhere");

// Narrative copy reads its numbers from the generated data so the prose
// cannot drift from the charts when the aggregates are refreshed.
const viewToCartStage = funnelStage("add_to_cart");
const sequenceGapCount = numberFormat.format(sequenceGap.numeratorSessions);
const topPage = data.pageOpportunities[0];
const smallestMde = data.mdeSensitivity[0];
const dailyPeeking = data.peeking.reduce((most, row) =>
  row.looks > most.looks ? row : most,
);
const maxBoundary = Math.max(
  ...data.sequentialBoundaries.map((row) => row.zBoundary),
);

// Planner inputs. Z values are fixed so the server render and the browser
// agree exactly; power options match the precomputed inflation factors.
const Z_ALPHA = 1.959963984540054;
type PlannerPower = "0.70" | "0.80" | "0.90";
const Z_POWER: Record<PlannerPower, number> = {
  "0.70": 0.5244005127080407,
  "0.80": 0.8416212335729143,
  "0.90": 1.2815515655446004,
};
const plannerPowers: PlannerPower[] = ["0.70", "0.80", "0.90"];
type PlannerLooks = keyof typeof data.planner.inflationFactors;
const plannerLooks = Object.keys(
  data.planner.inflationFactors,
) as PlannerLooks[];

function normalCdf(value: number): number {
  // Abramowitz and Stegun 7.1.26 erf approximation (absolute error < 1.5e-7).
  const x = Math.abs(value) / Math.SQRT2;
  const t = 1 / (1 + 0.3275911 * x);
  const erf =
    1 -
    ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t -
      0.284496736) *
      t +
      0.254829592) *
      t *
      Math.exp(-x * x);
  return value >= 0 ? 0.5 * (1 + erf) : 0.5 * (1 - erf);
}

function planExperiment(
  mdePp: number,
  marginPp: number,
  power: PlannerPower,
  looks: PlannerLooks,
) {
  const {
    baselineRate,
    paymentErrorRate,
    unitsPerDay,
    operationalBuffer,
    inflationFactors,
    unadjustedFalsePositiveRates,
  } = data.planner;
  const lift = mdePp / 100;
  const margin = marginPp / 100;
  const treatmentRate = baselineRate + lift;
  const zPower = Z_POWER[power];
  const primaryVariance =
    baselineRate * (1 - baselineRate) + treatmentRate * (1 - treatmentRate);
  const guardrailVariance = 2 * paymentErrorRate * (1 - paymentErrorRate);
  const midpoint = (baselineRate + treatmentRate) / 2;
  const primaryOnly = Math.ceil(
    (Z_ALPHA * Math.sqrt(2 * midpoint * (1 - midpoint)) +
      zPower * Math.sqrt(primaryVariance)) **
      2 /
      lift ** 2,
  );
  const guardrailOnly = Math.ceil(
    ((Z_ALPHA + zPower) ** 2 * guardrailVariance) / margin ** 2,
  );

  // Smallest per-arm sample, in steps of 10, where both tests pass with the
  // target joint probability (normal approximation, independent outcomes).
  let perArm = 10;
  while (perArm < 2_000_000) {
    const primary = normalCdf(
      lift / Math.sqrt(primaryVariance / perArm) - Z_ALPHA,
    );
    const guardrail = normalCdf(
      margin / Math.sqrt(guardrailVariance / perArm) - Z_ALPHA,
    );
    if (primary * guardrail >= Number(power)) {
      break;
    }
    perArm += 10;
  }
  const enrollmentPerArm = Math.ceil(
    Math.ceil(perArm * inflationFactors[looks][power]) *
      (1 + operationalBuffer),
  );
  const enrollmentTotal = 2 * enrollmentPerArm;
  const requirementRatio = guardrailOnly / primaryOnly;
  return {
    enrollmentTotal,
    weeks: enrollmentTotal / unitsPerDay / 7,
    bindingConstraint:
      requirementRatio > 1.25
        ? "Guardrail"
        : requirementRatio < 0.8
          ? "Primary metric"
          : "Both tests",
    unadjustedFalsePositiveRate: unadjustedFalsePositiveRates[looks],
  };
}


export function Dashboard() {
  const [funnelMode, setFunnelMode] = useState<FunnelMode>("step");
  const [segmentType, setSegmentType] = useState<SegmentType>("Device");
  const [segmentMetric, setSegmentMetric] =
    useState<SegmentMetric>("purchase_session_conversion");
  const [telemetryType, setTelemetryType] =
    useState<SegmentType>("Device");
  const [scenarioLiftPp, setScenarioLiftPp] = useState(0.5);

  const selectedSegmentRows = useMemo(
    () =>
      data.segments
        .filter(
          (row) =>
            row.segmentType === segmentType &&
            row.metricName === segmentMetric,
        )
        .sort((left, right) => right.conversionRate - left.conversionRate),
    [segmentMetric, segmentType],
  );

  const maxSegmentRate = Math.max(
    ...selectedSegmentRows.map((row) => row.conversionRate),
    0.0001,
  );

  const selectedTelemetryRows = useMemo(
    () =>
      data.telemetrySegments
        .filter((row) => row.segmentType === telemetryType)
        .sort((left, right) => right.gapRate - left.gapRate),
    [telemetryType],
  );

  const maxTelemetryRate = Math.max(
    ...selectedTelemetryRows.map((row) => row.gapRate),
    0.0001,
  );

  const retentionRows = data.retention.filter((row) => row.week > 0);
  const firstRetention = retentionRows[0];
  const lastRetention = retentionRows[retentionRows.length - 1];
  const maxRetentionRate = Math.max(
    ...retentionRows.map((row) => row.rate),
    0.0001,
  );

  const scenarioOrders =
    data.kpis.checkoutSessions * (scenarioLiftPp / 100);
  const scenarioRevenue =
    scenarioOrders * data.kpis.averageOrderValueUsd;

  const segmentInsight = useMemo(() => {
    if (segmentMetric !== "purchase_session_conversion") {
      return {
        title: "Read intervals before ranking",
        copy:
          "Segment differences are descriptive. Use the 95% intervals and denominator sizes before treating a visual gap as material.",
      };
    }

    if (segmentType === "Device") {
      const mobile = selectedSegmentRows.find(
        (row) => row.segmentValue === "mobile",
      );
      const desktop = selectedSegmentRows.find(
        (row) => row.segmentValue === "desktop",
      );
      if (mobile && desktop) {
        return {
          title:
            mobile.conversionRate >= desktop.conversionRate
              ? "No observed mobile deficit"
              : "Mobile trails desktop",
          copy: `Mobile converted at ${formatPercent(
            mobile.conversionRate,
          )} versus ${formatPercent(
            desktop.conversionRate,
          )} on desktop. The ${formatPp(
            (mobile.conversionRate - desktop.conversionRate) * 100,
          )} descriptive difference is not a product-treatment effect.`,
        };
      }
    }

    const returning = selectedSegmentRows.find(
      (row) => row.segmentValue === "Returning",
    );
    const newUsers = selectedSegmentRows.find(
      (row) => row.segmentValue === "New",
    );
    if (returning && newUsers) {
      return {
        title: "Familiarity is the largest segment signal",
        copy: `Returning sessions converted at ${formatPercent(
          returning.conversionRate,
        )} versus ${formatPercent(
          newUsers.conversionRate,
        )} for New. The ${formatPp(
          (returning.conversionRate - newUsers.conversionRate) * 100,
        )} gap is an association, not a causal effect.`,
      };
    }

    return {
      title: "Descriptive comparison",
      copy:
        "The selected rows meet the dashboard reporting threshold, but historical composition can still explain the difference.",
    };
  }, [segmentMetric, segmentType, selectedSegmentRows]);

  return (
    <main className="dashboard-shell">
      <div className="background-block background-block-one" />
      <div className="background-block background-block-two" />

      <section className="hero" id="top">
        <header className="topbar">
          <a className="brand" href="#top" aria-label="Product Growth home">
            <span className="brand-icon">
              <BarChart3 aria-hidden="true" size={18} strokeWidth={2.4} />
            </span>
            <span>
              Product Growth
              <small>Decision dashboard</small>
            </span>
          </a>

          <nav aria-label="Dashboard sections">
            <a href="#funnel">Funnel</a>
            <a href="#segments">Segments</a>
            <a href="#telemetry">Telemetry</a>
            <a href="#experiment">Experiment</a>
          </nav>
        </header>

        <div className="hero-grid">
          <div className="hero-copy">
            <div className="eyebrow">
              <span className="status-dot" />
              Historical GA4 evidence ·{" "}
              {data.metadata.observedCalendarDays} observed days
            </div>
            <h1>
              Test a simpler checkout.
              <span>Do not claim the cause yet.</span>
            </h1>
            <p className="hero-lede">
              Checkout is the most actionable next experiment, but the apparent{" "}
              {sequenceGapCount}-purchase telemetry gap is a sequence and
              re-entry artifact—not {sequenceGapCount} abandoned purchases.
            </p>
            <div className="hero-actions">
              <a className="primary-action" href="#experiment">
                Review test design
                <ArrowRight aria-hidden="true" size={17} />
              </a>
              <a className="text-action" href="#funnel">
                Inspect evidence
                <ArrowDownRight aria-hidden="true" size={17} />
              </a>
            </div>
          </div>

          <aside className="decision-card" aria-label="Primary decision">
            <div className="decision-card-header">
              <span>Decision 01</span>
              <span className="decision-status">Conditional go</span>
            </div>
            <h2>Advance simplified checkout to A/B design</h2>
            <p>
              Keep the historical analysis descriptive and require sticky,
              user-level exposure before launch.
            </p>
            <div className="decision-proof">
              <div>
                <CheckCircle2 aria-hidden="true" size={18} />
                <span>
                  <strong>{formatPercent(checkoutPurchase.rate)}</strong>
                  checkout → purchase
                </span>
              </div>
              <div>
                <ShieldCheck aria-hidden="true" size={18} />
                <span>
                  <strong>43 / 43</strong>
                  hard reconciliations passed
                </span>
              </div>
              <div>
                <FlaskConical aria-hidden="true" size={18} />
                <span>
                  <strong>
                    {numberFormat.format(data.experimentPlan.enrollmentTotal)}
                  </strong>
                  max experiment users
                </span>
              </div>
            </div>
          </aside>
        </div>

        <div className="source-strip">
          <span>
            <Database aria-hidden="true" size={15} />
            Google GA4 public ecommerce sample
          </span>
          <span>
            {data.metadata.analysisStartDate} →{" "}
            {data.metadata.analysisEndDate}
          </span>
          <span>{data.metadata.privacy}</span>
        </div>
      </section>

      <section className="section kpi-section" aria-labelledby="kpi-title">
        <div className="section-heading compact">
          <div>
            <span className="section-index">01 / Metric tree</span>
            <h2 id="kpi-title">Business performance at a glance</h2>
          </div>
          <p>
            Revenue is read through traffic, purchase conversion, and order
            value—not as a standalone total.
          </p>
        </div>

        <div className="kpi-grid">
          <KpiCard
            icon={<UsersRound aria-hidden="true" size={19} />}
            label="Sessions"
            value={numberFormat.format(data.kpis.sessions)}
            note={`${numberFormat.format(data.kpis.users)} pseudonymous users`}
          />
          <KpiCard
            icon={<PackageSearch aria-hidden="true" size={19} />}
            label="Product-view reach"
            value={formatPercent(
              data.kpis.productViewSessions / data.kpis.sessions,
              1,
            )}
            note={`${numberFormat.format(
              data.kpis.productViewSessions,
            )} sessions`}
          />
          <KpiCard
            icon={<ShoppingCart aria-hidden="true" size={19} />}
            label="Purchase / session"
            value={formatPercent(data.kpis.purchaseSessionRate)}
            note={`${numberFormat.format(
              data.kpis.purchasingSessions,
            )} purchasing sessions`}
          />
          <KpiCard
            icon={<Layers3 aria-hidden="true" size={19} />}
            label="Clean orders"
            value={numberFormat.format(data.kpis.orders)}
            note="Canonical transaction population"
          />
          <KpiCard
            icon={<CircleDollarSign aria-hidden="true" size={19} />}
            label="Revenue"
            value={currencyFormat.format(data.kpis.revenueUsd)}
            note={`${currencyFormat.format(
              data.kpis.revenuePerSessionUsd,
            )} per session`}
          />
          <KpiCard
            icon={<Gauge aria-hidden="true" size={19} />}
            label="Average order value"
            value={currencyFormat.format(data.kpis.averageOrderValueUsd)}
            note="Gross revenue / clean orders"
          />
        </div>

        <div className="monthly-panel">
          <div className="monthly-intro">
            <span>Monthly shape</span>
            <strong>December led; January softened.</strong>
            <p>
              This is sample-period context, not evidence of seasonality or
              current performance.
            </p>
          </div>
          {data.monthly.map((month) => (
            <div className="month-card" key={month.month}>
              <div>
                <span>{formatMonth(month.month)}</span>
                <strong>{compactNumberFormat.format(month.sessions)}</strong>
                <small>sessions</small>
              </div>
              <div>
                <span>Purchase / session</span>
                <strong>{formatPercent(month.purchaseSessionRate)}</strong>
              </div>
              <div>
                <span>Revenue</span>
                <strong>{currencyFormat.format(month.revenueUsd)}</strong>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="section" id="funnel" aria-labelledby="funnel-title">
        <div className="section-heading">
          <div>
            <span className="section-index">02 / Ordered funnel</span>
            <h2 id="funnel-title">The largest absolute loss comes first</h2>
          </div>
          <div
            className="segmented-control"
            role="group"
            aria-label="Funnel rate view"
          >
            <button
              type="button"
              aria-pressed={funnelMode === "step"}
              onClick={() => setFunnelMode("step")}
            >
              Step rate
            </button>
            <button
              type="button"
              aria-pressed={funnelMode === "cumulative"}
              onClick={() => setFunnelMode("cumulative")}
            >
              Cumulative
            </button>
          </div>
        </div>

        <div className="funnel-layout">
          <div className="funnel-chart">
            {data.funnel.map((stage) => {
              const displayRate =
                funnelMode === "step"
                  ? stage.stepConversionRate
                  : stage.cumulativeConversionRate;
              const width =
                (stage.sessions / data.funnel[0].sessions) * 100;
              const isPrimaryLoss = stage.stageName === "add_to_cart";

              return (
                <article
                  className={`funnel-row ${
                    isPrimaryLoss ? "is-primary-loss" : ""
                  }`}
                  key={stage.stageName}
                >
                  <div className="funnel-label">
                    <span>{String(stage.stageIndex).padStart(2, "0")}</span>
                    <div>
                      <strong>
                        {stageLabels[stage.stageName] ?? stage.stageName}
                      </strong>
                      <small>
                        {numberFormat.format(stage.sessions)} sessions
                      </small>
                    </div>
                  </div>
                  <div className="funnel-bar-track">
                    <div
                      className="funnel-bar"
                      style={barStyle(Math.max(width, 4))}
                    />
                  </div>
                  <div className="funnel-rate">
                    <strong>{formatPercent(displayRate)}</strong>
                    <span>
                      {stage.stageIndex === 1
                        ? "entry base"
                        : `${numberFormat.format(
                            stage.lostSessions,
                          )} lost`}
                    </span>
                  </div>
                </article>
              );
            })}
          </div>

          <aside className="insight-card bottleneck-card">
            <span className="insight-label">Largest observed loss</span>
            <strong>
              {numberFormat.format(viewToCartStage.lostSessions)} sessions
            </strong>
            <h3>View item → add to cart</h3>
            <p>
              Only {formatPercent(viewToCartStage.stepConversionRate)} of
              product-view sessions proceed to cart. This is the broadest
              behavioral loss, while checkout remains the clearer intervention
              to test.
            </p>
            <div className="insight-rule">
              <Info aria-hidden="true" size={17} />
              <span>
                Largest loss ≠ automatic priority. Reach, evidence strength,
                actionability, and measurement quality all matter.
              </span>
            </div>
          </aside>
        </div>
      </section>

      <section
        className="section section-tinted"
        id="segments"
        aria-labelledby="segments-title"
      >
        <div className="section-heading">
          <div>
            <span className="section-index">03 / Segment diagnosis</span>
            <h2 id="segments-title">Composition matters more than device</h2>
          </div>
          <div
            className="segmented-control"
            role="group"
            aria-label="Segment dimension"
          >
            <button
              type="button"
              aria-pressed={segmentType === "Device"}
              onClick={() => setSegmentType("Device")}
            >
              Device
            </button>
            <button
              type="button"
              aria-pressed={segmentType === "User tenure"}
              onClick={() => setSegmentType("User tenure")}
            >
              New / Returning
            </button>
          </div>
        </div>

        <div className="metric-tabs" role="group" aria-label="Segment metric">
          {metricOptions.map((option) => (
            <button
              type="button"
              key={option.value}
              aria-pressed={segmentMetric === option.value}
              onClick={() => setSegmentMetric(option.value)}
            >
              {option.label}
            </button>
          ))}
        </div>

        <div className="segment-layout">
          <div className="segment-chart">
            {selectedSegmentRows.map((row) => (
              <article className="segment-row" key={row.segmentValue}>
                <div className="segment-name">
                  <strong>{row.segmentValue}</strong>
                  <span>
                    n = {numberFormat.format(row.denominatorSessions)}
                  </span>
                </div>
                <div className="segment-bar-track">
                  <div
                    className="segment-bar"
                    style={barStyle(
                      (row.conversionRate / maxSegmentRate) * 100,
                    )}
                  />
                </div>
                <div className="segment-value">
                  <strong>{formatPercent(row.conversionRate)}</strong>
                  <span>
                    {formatPercent(row.ci95Lower)}–
                    {formatPercent(row.ci95Upper)}
                  </span>
                </div>
              </article>
            ))}
          </div>

          <aside className="insight-card">
            <span className="insight-label">What changes the decision?</span>
            <h3>{segmentInsight.title}</h3>
            <p>{segmentInsight.copy}</p>
            <div className="insight-rule">
              <ShieldCheck aria-hidden="true" size={17} />
              <span>
                Reported rows meet governed denominators; comparisons remain
                observational.
              </span>
            </div>
          </aside>
        </div>
      </section>

      <section
        className="section"
        id="opportunities"
        aria-labelledby="opportunities-title"
      >
        <div className="section-heading">
          <div>
            <span className="section-index">04 / Product opportunity</span>
            <h2 id="opportunities-title">
              High-traffic PDPs show focused upside
            </h2>
          </div>
          <p>
            Scenario: each eligible page reaches the unweighted P75 view-to-add
            benchmark of {formatPercent(topPage.benchmarkRate)}.
          </p>
        </div>

        <div className="opportunity-layout">
          <div className="opportunity-list">
            <div className="opportunity-header">
              <span>Rank / product detail page</span>
              <span>View → add</span>
              <span>Scenario orders</span>
            </div>
            {data.pageOpportunities.slice(0, 5).map((page) => (
              <article className="opportunity-row" key={page.rank}>
                <span className="opportunity-rank">
                  {String(page.rank).padStart(2, "0")}
                </span>
                <div className="opportunity-name">
                  <strong>{page.title}</strong>
                  <span>
                    {numberFormat.format(page.viewSessions)} view sessions
                  </span>
                </div>
                <div className="opportunity-rate">
                  <strong>{formatPercent(page.viewToAddRate)}</strong>
                  <span>vs {formatPercent(page.benchmarkRate)}</span>
                </div>
                <div className="opportunity-orders">
                  <strong>+{page.scenarioIncrementalOrders.toFixed(1)}</strong>
                  <span>
                    {currencyFormat.format(page.scenarioRevenueUsd)}
                  </span>
                </div>
              </article>
            ))}
          </div>

          <aside className="top-opportunity">
            <Target aria-hidden="true" size={22} />
            <span className="insight-label">Top governed scenario</span>
            <h3>{topPage.title}</h3>
            <div className="opportunity-number">
              +{topPage.scenarioIncrementalOrders.toFixed(1)}
              <span>orders in the historical-window scenario</span>
            </div>
            <p>
              This page combines {numberFormat.format(topPage.viewSessions)}{" "}
              views with a {formatPercent(topPage.viewToAddRate)} view-to-add
              rate. It is a prioritization signal, not a forecast.
            </p>
            <div className="warning-note">
              <Info aria-hidden="true" size={17} />
              Page opportunity values are non-additive because sessions can
              view multiple PDPs.
            </div>
          </aside>
        </div>
      </section>

      <section
        className="section telemetry-section"
        id="telemetry"
        aria-labelledby="telemetry-title"
      >
        <div className="section-heading inverted">
          <div>
            <span className="section-index">05 / Checkout telemetry</span>
            <h2 id="telemetry-title">
              {`The ${sequenceGapCount}-session gap is not abandonment`}
            </h2>
          </div>
          <p>
            Re-entry and repeated begin_checkout events make strict event order
            an unreliable outcome definition.
          </p>
        </div>

        <div className="telemetry-overview">
          <div className="telemetry-composition">
            <div className="telemetry-title-row">
              <div>
                <span>Purchases after governed checkout</span>
                <strong>
                  {numberFormat.format(checkoutPurchase.numeratorSessions)}
                </strong>
              </div>
              <div>
                <span>Checkout sessions</span>
                <strong>
                  {numberFormat.format(checkoutPurchase.denominatorSessions)}
                </strong>
              </div>
            </div>
            <div
              className="composition-bar"
              role="img"
              aria-label={`${formatPercent(
                strictCoverage.rate,
              )} strict sequence and ${formatPercent(
                sequenceGap.rate,
              )} sequence gap among purchases`}
            >
              <span
                className="composition-strict"
                style={barStyle(strictCoverage.rate * 100)}
              />
              <span
                className="composition-gap"
                style={barStyle(sequenceGap.rate * 100)}
              />
            </div>
            <div className="composition-legend">
              <span>
                <i className="legend-strict" />
                Strict sequence
                <strong>{formatPercent(strictCoverage.rate)}</strong>
              </span>
              <span>
                <i className="legend-gap" />
                Sequence gap
                <strong>{formatPercent(sequenceGap.rate)}</strong>
              </span>
            </div>
          </div>

          <div className="telemetry-facts">
            <TelemetryFact
              value={formatPercent(repeatedCheckout.rate)}
              label="checkout sessions had repeated begin_checkout"
            />
            <TelemetryFact
              value={formatPercent(gapShippingBefore.rate, 0)}
              label="gap purchases had shipping at/before checkout"
            />
            <TelemetryFact
              value={formatPercent(gapPaymentBefore.rate, 0)}
              label="gap purchases had payment before purchase"
            />
            <TelemetryFact
              value={numberFormat.format(gapNoShipping.numeratorSessions)}
              label="gap purchases lacked shipping everywhere"
            />
          </div>
        </div>

        <div className="telemetry-segment-panel">
          <div className="telemetry-segment-heading">
            <div>
              <span>Sequence-gap rate among purchases</span>
              <strong>Not concentrated in a broad segment</strong>
            </div>
            <div
              className="segmented-control dark"
              role="group"
              aria-label="Telemetry segment dimension"
            >
              <button
                type="button"
                aria-pressed={telemetryType === "Device"}
                onClick={() => setTelemetryType("Device")}
              >
                Device
              </button>
              <button
                type="button"
                aria-pressed={telemetryType === "User tenure"}
                onClick={() => setTelemetryType("User tenure")}
              >
                New / Returning
              </button>
            </div>
          </div>

          <div className="telemetry-segment-grid">
            {selectedTelemetryRows.map((row) => (
              <article key={row.segmentValue}>
                <div>
                  <strong>{row.segmentValue}</strong>
                  <span>
                    {numberFormat.format(row.purchaseSessions)} purchases
                  </span>
                </div>
                <div className="telemetry-bar-track">
                  <div
                    className="telemetry-bar"
                    style={barStyle((row.gapRate / maxTelemetryRate) * 100)}
                  />
                </div>
                <strong>{formatPercent(row.gapRate)}</strong>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section
        className="section experiment-section"
        id="experiment"
        aria-labelledby="experiment-title"
      >
        <div className="section-heading">
          <div>
            <span className="section-index">06 / Experiment design</span>
            <h2 id="experiment-title">
              Design-ready; instrumentation pending
            </h2>
          </div>
          <div className="readiness-badge">
            <span />
            Not launch-ready
          </div>
        </div>

        <div className="experiment-grid">
          <article className="experiment-plan-card">
            <div className="card-icon">
              <FlaskConical aria-hidden="true" size={21} />
            </div>
            <span className="insight-label">Pre-registered plan</span>
            <h3>+{data.experimentPlan.plannedMdePp.toFixed(0)} pp MDE</h3>
            <p className="plan-subtitle">
              {data.experimentPlan.plannedLooks} planned looks · O&apos;Brien-Fleming
              boundaries · payment-error margin{" "}
              {formatPp(data.experimentPlan.paymentErrorMarginPp, 1)}
            </p>
            <div className="plan-stat-grid">
              <div>
                <strong>
                  {numberFormat.format(data.experimentPlan.enrollmentTotal)}
                </strong>
                <span>users at most</span>
              </div>
              <div>
                <strong>{data.experimentPlan.maxProxyWeeks.toFixed(1)}</strong>
                <span>max proxy weeks</span>
              </div>
              <div>
                <strong>
                  {data.experimentPlan.expectedWeeksIfEffective.toFixed(1)}
                </strong>
                <span>expected weeks if it works</span>
              </div>
              <div>
                <strong>
                  {formatPercent(data.experimentPlan.shipProbabilityAtMde, 0)}
                </strong>
                <span>chance a true +5 pp lift ships</span>
              </div>
            </div>
            <p className="plan-rule">
              Ship only when the lift crosses the look&apos;s boundary and the
              payment-error bound stays inside the margin. A no-effect change
              ships {formatPercent(data.experimentPlan.shipProbabilityNoEffect, 1)}{" "}
              of the time; one that raises payment errors by the full margin,{" "}
              {formatPercent(data.experimentPlan.shipProbabilityHarmful, 1)}.
            </p>
            <div className="exposure-rule">
              <ShieldCheck aria-hidden="true" size={18} />
              <span>
                Randomize by user with a sticky experiment_exposure event.
                Repeated checkout starts must never reset assignment.
              </span>
            </div>
          </article>

          <article className="scenario-card">
            <div className="scenario-heading">
              <div>
                <span className="insight-label">
                  Historical-window scenario
                </span>
                <h3>What if checkout improves?</h3>
              </div>
              <TrendingUp aria-hidden="true" size={23} />
            </div>

            <label htmlFor="lift-range">
              Absolute checkout-completion lift
              <output htmlFor="lift-range">
                +{scenarioLiftPp.toFixed(2)} pp
              </output>
            </label>
            <input
              id="lift-range"
              type="range"
              min="0.25"
              max="5"
              step="0.25"
              value={scenarioLiftPp}
              aria-valuetext={formatPp(scenarioLiftPp)}
              onChange={(event) =>
                setScenarioLiftPp(Number(event.target.value))
              }
            />
            <div className="range-scale">
              <span>+0.25 pp</span>
              <span>+5.00 pp</span>
            </div>

            <div className="scenario-output">
              <div>
                <strong>+{scenarioOrders.toFixed(1)}</strong>
                <span>incremental orders</span>
              </div>
              <div>
                <strong>{currencyFormat.format(scenarioRevenue)}</strong>
                <span>incremental gross revenue</span>
              </div>
            </div>
            <p>
              Uses {numberFormat.format(data.kpis.checkoutSessions)} historical
              checkout sessions and {currencyFormat.format(
                data.kpis.averageOrderValueUsd,
              )}{" "}
              AOV. This is a scenario, not a forecast.
            </p>
          </article>
        </div>

        <div className="audit-panel">
          <div className="audit-copy">
            <span className="insight-label">Decision-rule audit</span>
            <h3>
              {`The first plan would ship a real +5 pp winner only ${formatPercent(
                data.originalPlanAudit.shipProbabilityAtMde,
                0,
              )} of the time`}
            </h3>
            <p>
              It enrolled{" "}
              {numberFormat.format(data.originalPlanAudit.enrollmentTotal)} users
              and was powered for significance alone, then also required the
              estimate to clear +5 pp and an unsized payment-error check. A
              seeded simulation of the whole rule exposed the gap.
            </p>
            <div className="audit-factors">
              <AuditFactor
                label="Interval above zero"
                value={data.originalPlanAudit.primaryIntervalAtMde}
              />
              <AuditFactor
                label="Estimate at least +5 pp"
                value={data.originalPlanAudit.pointEstimateAtMde}
              />
              <AuditFactor
                label="Payment-error check passes"
                value={data.originalPlanAudit.guardrailAtMde}
              />
              <AuditFactor
                label="All three: ships"
                value={data.originalPlanAudit.shipProbabilityAtMde}
                emphasis
              />
            </div>
            <p className="audit-fix">
              The fix: ship on a significant lift instead of a point-estimate
              hurdle, and size the test for the payment-error guardrail too.
              When a true winner still fails to ship, the guardrail is usually
              why ({formatPercent(data.experimentPlan.guardrailBlockAtMde, 0)} of
              runs).
            </p>
          </div>
          <DecisionAuditChart />
        </div>

        <div className="monitoring-panel">
          <div className="mde-copy">
            <span className="insight-label">Monitoring without p-hacking</span>
            <h3>
              {`Checking daily would push false positives to ${formatPercent(
                dailyPeeking.falsePositiveRate,
                0,
              )}`}
            </h3>
            <p>
              Every unplanned look is another chance for noise to cross the
              line. Four planned looks with O&apos;Brien-Fleming boundaries keep
              the overall rate at 5%, let a clear result stop early, and stop
              the test at the halfway look if the lift is not positive.
            </p>
            <div className="peeking-list">
              {data.peeking.map((row) => (
                <div className="peeking-row" key={row.monitoring}>
                  <span>{row.monitoring}</span>
                  <strong>{formatPercent(row.falsePositiveRate, 1)}</strong>
                </div>
              ))}
            </div>
          </div>
          <div className="boundary-list">
            <div className="boundary-header">
              <span>Look</span>
              <span>Proxy week</span>
              <span>Users</span>
              <span>z needed to ship</span>
            </div>
            {data.sequentialBoundaries.map((row) => (
              <div className="boundary-row" key={row.look}>
                <span>{row.look}</span>
                <span>{row.proxyWeek.toFixed(1)}</span>
                <span>{numberFormat.format(row.enrolledTotal)}</span>
                <div className="boundary-value">
                  <div className="mde-bar-track">
                    <div
                      className="mde-bar"
                      style={barStyle((row.zBoundary / maxBoundary) * 100)}
                    />
                  </div>
                  <strong>{row.zBoundary.toFixed(2)}</strong>
                </div>
              </div>
            ))}
            <p className="boundary-note">
              A fixed-sample test would use 1.96 at a single final read.
              Expected duration:{" "}
              {data.experimentPlan.expectedWeeksIfEffective.toFixed(1)} weeks if
              the lift is real,{" "}
              {data.experimentPlan.expectedWeeksIfNoEffect.toFixed(1)} weeks if
              it is not.
            </p>
          </div>
        </div>

        <ExperimentPlanner />

        <div className="mde-panel">
          <div className="mde-copy">
            <span className="insight-label">Detectability trade-off</span>
            <h3>Small effects are not feasible at this traffic proxy</h3>
            <p>
              A {formatPp(smallestMde.absoluteMdePp)} product scenario would need
              roughly {numberFormat.format(smallestMde.requiredTotal)} units and{" "}
              {numberFormat.format(Math.round(smallestMde.proxyWeeks))} proxy
              weeks for the primary metric alone. Opportunity size and
              experimental detectability are separate decisions.
            </p>
          </div>
          <div className="mde-list">
            {data.mdeSensitivity.map((row) => (
              <div className="mde-row" key={row.absoluteMdePp}>
                <span>+{row.absoluteMdePp.toFixed(1)} pp</span>
                <div className="mde-bar-track">
                  <div
                    className="mde-bar"
                    style={barStyle(
                      Math.max(
                        4,
                        (Math.log10(row.requiredTotal) /
                          Math.log10(
                            data.mdeSensitivity[0].requiredTotal,
                          )) *
                          100,
                      ),
                    )}
                  />
                </div>
                <strong>{numberFormat.format(row.requiredTotal)}</strong>
                <span>{row.proxyWeeks.toFixed(1)} wk</span>
              </div>
            ))}
          </div>
        </div>

        <aside className="simulation-strip">
          <div className="simulation-label">
            <FlaskConical aria-hidden="true" size={20} />
            <span>
              <strong>Simulation only</strong>
              Seed {data.simulationOnly.seed}; true lift{" "}
              {formatPp(data.simulationOnly.trueLiftPp)}; no causal evidence
            </span>
          </div>
          <div>
            <span>Control</span>
            <strong>{formatPercent(data.simulationOnly.controlRate)}</strong>
          </div>
          <ArrowRight aria-hidden="true" size={18} />
          <div>
            <span>Treatment</span>
            <strong>{formatPercent(data.simulationOnly.treatmentRate)}</strong>
          </div>
          <div className="simulation-effect">
            <span>
              Look {data.simulationOnly.stoppingLook} of{" "}
              {data.simulationOnly.plannedLooks}: lift{" "}
              {formatPp(data.simulationOnly.differencePp)} (z{" "}
              {data.simulationOnly.zStatistic.toFixed(2)} vs{" "}
              {data.simulationOnly.zBoundary.toFixed(2)})
            </span>
            <strong>{data.simulationOnly.decision}</strong>
            <small>
              Payment-error bound{" "}
              {formatPp(data.simulationOnly.paymentErrorUpperPp)} against a{" "}
              {formatPp(data.simulationOnly.paymentErrorMarginPp)} margin. A
              real winner is blocked this way{" "}
              {formatPercent(data.experimentPlan.guardrailBlockAtMde, 0)} of the
              time.
            </small>
          </div>
        </aside>
      </section>

      <section
        className="section section-tinted"
        id="retention"
        aria-labelledby="retention-title"
      >
        <div className="section-heading">
          <div>
            <span className="section-index">07 / Observed retention</span>
            <h2 id="retention-title">Return behavior decays quickly</h2>
          </div>
          <p>
            Pooled weekly activity retention among complete follow-up cohorts;
            observed within the sample window.
          </p>
        </div>

        <div className="retention-layout">
          <div className="retention-chart">
            {retentionRows.map((row) => (
              <article className="retention-row" key={row.week}>
                <span>W{row.week}</span>
                <div className="retention-bar-track">
                  <div
                    className="retention-bar"
                    style={barStyle((row.rate / maxRetentionRate) * 100)}
                  />
                </div>
                <strong>{formatPercent(row.rate)}</strong>
                <small>{row.completeCohorts} complete cohorts</small>
              </article>
            ))}
          </div>
          <aside className="retention-callout">
            <span>W{firstRetention.week} observed retention</span>
            <strong>{formatPercent(firstRetention.rate)}</strong>
            <p>
              W{lastRetention.week} falls to{" "}
              {formatPercent(lastRetention.rate)}. This informs future traffic
              expectations; it is not lifetime value.
            </p>
          </aside>
        </div>
      </section>

      <section className="section data-section" aria-labelledby="data-title">
        <div className="section-heading compact">
          <div>
            <span className="section-index">08 / Reproducibility</span>
            <h2 id="data-title">Use the same governed aggregates</h2>
          </div>
          <p>
            Downloadable extracts are suitable for Tableau, Power BI, or
            independent review. No user- or session-level rows are published.
          </p>
        </div>

        <div className="download-grid">
          <DownloadCard
            href="/data/kpi_summary.csv"
            title="Metric tree"
            copy="Traffic, conversion, AOV, and revenue KPIs."
          />
          <DownloadCard
            href="/data/funnel_overall.csv"
            title="Ordered funnel"
            copy="Four stage counts, losses, and conversion rates."
          />
          <DownloadCard
            href="/data/segment_funnel.csv"
            title="Segment comparison"
            copy="Reportable Device and New / Returning rows."
          />
          <DownloadCard
            href="/data/data_manifest.csv"
            title="Data manifest"
            copy="Source run, row counts, privacy level, and hashes."
          />
        </div>
      </section>

      <footer>
        <div>
          <span className="brand footer-brand">
            <span className="brand-icon">
              <BarChart3 aria-hidden="true" size={18} />
            </span>
            Product Growth Analytics
          </span>
          <p>
            Decision dashboard built from aggregate-only Google GA4 public
            ecommerce sample data.
          </p>
        </div>
        <div className="footer-notes">
          <span>
            Historical sample · {formatMonth(data.metadata.analysisStartDate)}–
            {formatMonth(data.metadata.analysisEndDate)}
          </span>
          <span>Opportunity estimates are scenarios</span>
          <span>Experiment output is simulated</span>
        </div>
      </footer>
    </main>
  );
}


function KpiCard({
  icon,
  label,
  value,
  note,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  note: string;
}) {
  return (
    <article className="kpi-card">
      <div className="kpi-icon">{icon}</div>
      <span>{label}</span>
      <strong>{value}</strong>
      <small>{note}</small>
    </article>
  );
}


function TelemetryFact({
  value,
  label,
}: {
  value: string;
  label: string;
}) {
  return (
    <article>
      <strong>{value}</strong>
      <span>{label}</span>
    </article>
  );
}


function DownloadCard({
  href,
  title,
  copy,
}: {
  href: string;
  title: string;
  copy: string;
}) {
  return (
    <a className="download-card" href={href} download>
      <span className="download-icon">
        <Download aria-hidden="true" size={18} />
      </span>
      <div>
        <strong>{title}</strong>
        <span>{copy}</span>
      </div>
      <ArrowRight aria-hidden="true" size={18} />
    </a>
  );
}


function AuditFactor({
  label,
  value,
  emphasis = false,
}: {
  label: string;
  value: number;
  emphasis?: boolean;
}) {
  return (
    <div className={`audit-factor${emphasis ? " is-emphasis" : ""}`}>
      <span>{label}</span>
      <div className="audit-factor-track">
        <div className="audit-factor-bar" style={barStyle(value * 100)} />
      </div>
      <strong>{formatPercent(value, 0)}</strong>
    </div>
  );
}


const CHART = { width: 560, height: 300, left: 58, right: 18, top: 18, bottom: 46 };

function DecisionAuditChart() {
  const original = data.operatingCharacteristics.filter(
    (row) => row.design === "original_plan" && row.paymentHarmPp === 0,
  );
  const final = data.operatingCharacteristics.filter(
    (row) => row.design === "final_plan" && row.paymentHarmPp === 0,
  );
  const maxLift = Math.max(...final.map((row) => row.trueLiftPp));
  const mde = data.experimentPlan.plannedMdePp;
  const plotRight = CHART.width - CHART.right;
  const plotBottom = CHART.height - CHART.bottom;
  const x = (lift: number) =>
    CHART.left + (lift / maxLift) * (plotRight - CHART.left);
  const y = (probability: number) =>
    CHART.top + (1 - probability) * (plotBottom - CHART.top);
  const path = (rows: typeof final) =>
    rows
      .map(
        (row, index) =>
          `${index ? "L" : "M"}${x(row.trueLiftPp).toFixed(1)},${y(
            row.shipProbability,
          ).toFixed(1)}`,
      )
      .join(" ");
  const originalAtMde = original.find((row) => row.trueLiftPp === mde);
  const finalAtMde = final.find((row) => row.trueLiftPp === mde);
  const summary = `Probability that each rule ships the change, for true lifts from 0 to ${maxLift} percentage points. At a true +${mde} pp lift the original rule ships ${formatPercent(
    originalAtMde?.shipProbability ?? 0,
    0,
  )} of the time and the final plan ${formatPercent(
    finalAtMde?.shipProbability ?? 0,
    0,
  )}.`;

  return (
    <figure className="audit-chart">
      <svg
        viewBox={`0 0 ${CHART.width} ${CHART.height}`}
        role="img"
        aria-label={summary}
      >
        {[0, 0.2, 0.4, 0.6, 0.8, 1].map((tick) => (
          <g key={tick}>
            <line
              className="chart-grid"
              x1={CHART.left}
              x2={plotRight}
              y1={y(tick)}
              y2={y(tick)}
            />
            <text
              className="chart-tick"
              x={CHART.left - 8}
              y={y(tick)}
              dy="0.32em"
              textAnchor="end"
            >
              {`${Math.round(tick * 100)}%`}
            </text>
          </g>
        ))}
        {final.map((row) => (
          <text
            key={`tick-${row.trueLiftPp}`}
            className="chart-tick"
            x={x(row.trueLiftPp)}
            y={plotBottom + 18}
            textAnchor="middle"
          >
            {`+${row.trueLiftPp}`}
          </text>
        ))}
        <text
          className="chart-axis-label"
          x={(CHART.left + plotRight) / 2}
          y={CHART.height - 6}
          textAnchor="middle"
        >
          True lift in 24-hour conversion (pp)
        </text>
        <line
          className="chart-target"
          x1={CHART.left}
          x2={plotRight}
          y1={y(data.experimentPlan.targetPower)}
          y2={y(data.experimentPlan.targetPower)}
        />
        <line
          className="chart-mde"
          x1={x(mde)}
          x2={x(mde)}
          y1={CHART.top}
          y2={plotBottom}
        />
        <path className="chart-line original" d={path(original)} />
        <path className="chart-line final" d={path(final)} />
        {original.map((row) => (
          <circle
            key={`original-${row.trueLiftPp}`}
            className="chart-point original"
            cx={x(row.trueLiftPp)}
            cy={y(row.shipProbability)}
            r={3.5}
          />
        ))}
        {final.map((row) => (
          <circle
            key={`final-${row.trueLiftPp}`}
            className="chart-point final"
            cx={x(row.trueLiftPp)}
            cy={y(row.shipProbability)}
            r={3.5}
          />
        ))}
        {originalAtMde ? (
          <text
            className="chart-callout original"
            x={x(mde) + 9}
            y={y(originalAtMde.shipProbability)}
            dy="0.32em"
          >
            {formatPercent(originalAtMde.shipProbability, 0)}
          </text>
        ) : null}
        {finalAtMde ? (
          <text
            className="chart-callout final"
            x={x(mde) - 9}
            y={y(finalAtMde.shipProbability) - 12}
            textAnchor="end"
          >
            {formatPercent(finalAtMde.shipProbability, 0)}
          </text>
        ) : null}
      </svg>
      <figcaption className="chart-legend">
        <span>
          <i className="legend-line original" />
          {`Original rule (${numberFormat.format(
            data.originalPlanAudit.enrollmentTotal,
          )} users)`}
        </span>
        <span>
          <i className="legend-line final" />
          {`Final plan (up to ${numberFormat.format(
            data.experimentPlan.enrollmentTotal,
          )} users)`}
        </span>
        <span>
          <i className="legend-line target" />
          80% target · dashed line = +5 pp MDE
        </span>
      </figcaption>
    </figure>
  );
}


function ExperimentPlanner() {
  const [mdePp, setMdePp] = useState(data.experimentPlan.plannedMdePp);
  const [marginPp, setMarginPp] = useState(
    data.experimentPlan.paymentErrorMarginPp,
  );
  const [power, setPower] = useState<PlannerPower>("0.80");
  const [looks, setLooks] = useState<PlannerLooks>(
    String(data.experimentPlan.plannedLooks) as PlannerLooks,
  );
  const plan = useMemo(
    () => planExperiment(mdePp, marginPp, power, looks),
    [mdePp, marginPp, power, looks],
  );
  const peekingLabel =
    looks === "1"
      ? "false positives with one final read"
      : `false positives if all ${looks} looks used 1.96 (boundaries keep 5%)`;

  return (
    <div className="planner-panel">
      <div className="planner-copy">
        <span className="insight-label">Experiment planner</span>
        <h3>Change the assumptions</h3>
        <p>
          Closed-form estimate at the historical traffic proxy, with the 5%
          enrollment buffer. The plan of record (
          {numberFormat.format(data.experimentPlan.enrollmentTotal)} users)
          comes from simulating the full decision rules.
        </p>
      </div>

      <div className="planner-controls">
        <PlannerSlider
          id="planner-mde"
          label="Minimum detectable lift"
          value={mdePp}
          min={1}
          max={8}
          step={0.5}
          format={(value) => formatPp(value, 1)}
          onChange={setMdePp}
        />
        <PlannerSlider
          id="planner-margin"
          label="Payment-error margin"
          value={marginPp}
          min={1}
          max={3}
          step={0.25}
          format={(value) => formatPp(value, 2)}
          onChange={setMarginPp}
        />
        <div className="planner-choice">
          <span id="planner-power-label">Power</span>
          <div
            className="segmented-control"
            role="group"
            aria-labelledby="planner-power-label"
          >
            {plannerPowers.map((option) => (
              <button
                type="button"
                key={option}
                aria-pressed={power === option}
                onClick={() => setPower(option)}
              >
                {formatPercent(Number(option), 0)}
              </button>
            ))}
          </div>
        </div>
        <div className="planner-choice">
          <span id="planner-looks-label">Planned looks</span>
          <div
            className="segmented-control"
            role="group"
            aria-labelledby="planner-looks-label"
          >
            {plannerLooks.map((option) => (
              <button
                type="button"
                key={option}
                aria-pressed={looks === option}
                onClick={() => setLooks(option)}
              >
                {option}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="planner-output" aria-live="polite">
        <div>
          <strong>{numberFormat.format(plan.enrollmentTotal)}</strong>
          <span>users to enroll</span>
        </div>
        <div>
          <strong>{plan.weeks.toFixed(1)}</strong>
          <span>max proxy weeks</span>
        </div>
        <div>
          <strong>{plan.bindingConstraint}</strong>
          <span>binding constraint on the sample size</span>
        </div>
        <div>
          <strong>{formatPercent(plan.unadjustedFalsePositiveRate, 0)}</strong>
          <span>{peekingLabel}</span>
        </div>
      </div>
    </div>
  );
}


function PlannerSlider({
  id,
  label,
  value,
  min,
  max,
  step,
  format,
  onChange,
}: {
  id: string;
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  format: (value: number) => string;
  onChange: (value: number) => void;
}) {
  return (
    <div className="planner-slider">
      <label htmlFor={id}>
        {label}
        <output htmlFor={id}>{format(value)}</output>
      </label>
      <input
        id={id}
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        aria-valuetext={format(value)}
        onChange={(event) => onChange(Number(event.target.value))}
      />
    </div>
  );
}
