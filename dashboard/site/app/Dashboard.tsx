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

const monthLabels: Record<string, string> = {
  "2020-11": "Nov 2020",
  "2020-12": "Dec 2020",
  "2021-01": "Jan 2021",
};

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

function formatPp(value: number, digits = 2): string {
  const sign = value > 0 ? "+" : "";
  return `${sign}${value.toFixed(digits)} pp`;
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

const checkoutPurchase = telemetryMetric("checkout_purchase_rate");
const strictCoverage = telemetryMetric("strict_coverage_of_purchases");
const sequenceGap = telemetryMetric("purchase_sequence_gap");
const repeatedCheckout = telemetryMetric("repeated_checkout_start");
const gapShippingBefore = telemetryMetric("gap_shipping_before_checkout");
const gapPaymentBefore = telemetryMetric("gap_payment_before_purchase");
const gapNoShipping = telemetryMetric("gap_no_shipping_anywhere");


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
          title: "No observed mobile deficit",
          copy: `Mobile converted at ${formatPercent(
            mobile.conversionRate,
          )} versus ${formatPercent(
            desktop.conversionRate,
          )} on desktop. The +${(
            (mobile.conversionRate - desktop.conversionRate) *
            100
          ).toFixed(2)} pp descriptive difference is not a product-treatment effect.`,
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
              Historical GA4 evidence · 92 observed days
            </div>
            <h1>
              Test a simpler checkout.
              <span>Do not claim the cause yet.</span>
            </h1>
            <p className="hero-lede">
              Checkout is the most actionable next experiment, but the apparent
              941-purchase telemetry gap is a sequence and re-entry artifact—not
              941 abandoned purchases.
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
                  <strong>48.02%</strong>
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
                  <strong>3,296</strong>
                  buffered experiment target
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
                <span>{monthLabels[month.month] ?? month.month}</span>
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
          <div className="segmented-control" aria-label="Funnel rate view">
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
                    <span>0{stage.stageIndex}</span>
                    <div>
                      <strong>{stageLabels[stage.stageName]}</strong>
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
            <strong>62,640 sessions</strong>
            <h3>View item → add to cart</h3>
            <p>
              Only 18.67% of product-view sessions proceed to cart. This is the
              broadest behavioral loss, while checkout remains the clearer
              intervention to test.
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
          <div className="segmented-control" aria-label="Segment dimension">
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

        <div className="metric-tabs" aria-label="Segment metric">
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
            benchmark of 4.44%.
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
            <h3>{data.pageOpportunities[0].title}</h3>
            <div className="opportunity-number">
              +{data.pageOpportunities[0].scenarioIncrementalOrders.toFixed(1)}
              <span>orders in the historical-window scenario</span>
            </div>
            <p>
              This page combines 3,830 views with a 1.20% view-to-add rate. It
              is a prioritization signal, not a forecast.
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
            <h2 id="telemetry-title">The 941-session gap is not abandonment</h2>
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
            <span className="insight-label">Provisional planning contract</span>
            <h3>+{data.experimentPlan.plannedMdePp.toFixed(0)} pp MDE</h3>
            <div className="plan-stat-grid">
              <div>
                <strong>
                  {numberFormat.format(
                    data.experimentPlan.bufferedTargetPerArm,
                  )}
                </strong>
                <span>per arm, buffered</span>
              </div>
              <div>
                <strong>
                  {numberFormat.format(data.experimentPlan.bufferedTotal)}
                </strong>
                <span>total target</span>
              </div>
              <div>
                <strong>{data.experimentPlan.proxyWeeks.toFixed(2)}</strong>
                <span>proxy weeks</span>
              </div>
              <div>
                <strong>
                  {formatPercent(data.experimentPlan.targetPower, 0)}
                </strong>
                <span>target power</span>
              </div>
            </div>
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

        <div className="mde-panel">
          <div className="mde-copy">
            <span className="insight-label">Detectability trade-off</span>
            <h3>Small effects are not feasible at this traffic proxy</h3>
            <p>
              A +0.50 pp product scenario would need roughly 313,580 units and
              795 proxy weeks. Opportunity size and experimental detectability
              are separate decisions.
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
              Seed {data.simulationOnly.seed}; no causal evidence
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
            <span>Estimated difference</span>
            <strong>+{data.simulationOnly.differencePp.toFixed(2)} pp</strong>
            <small>
              95% CI +{data.simulationOnly.ci95LowerPp.toFixed(2)} to +
              {data.simulationOnly.ci95UpperPp.toFixed(2)} pp
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
            <span>W1 observed retention</span>
            <strong>{formatPercent(retentionRows[0].rate)}</strong>
            <p>
              W8 falls to{" "}
              {formatPercent(retentionRows[retentionRows.length - 1].rate)}.
              This informs future traffic expectations; it is not lifetime
              value.
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
          <span>Historical sample · Nov 2020–Jan 2021</span>
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
