import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";


async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}


test("server-renders the product decision dashboard", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(
    html,
    /<title>Product Growth Analytics \| Decision Dashboard<\/title>/i,
  );
  assert.match(html, /Test a simpler checkout/);
  assert.match(html, /The 941-session gap is not abandonment/);
  assert.match(html, /Design-ready; instrumentation pending/);
  assert.match(html, /Simulation only/);
  assert.match(html, /Aggregate-only; no user or session rows/);
  assert.doesNotMatch(html, /Your site is taking shape|Building your site/);
  assert.doesNotMatch(html, /react-loading-skeleton/);
});


test("dashboard data remains aggregate-only and reconciled", async () => {
  const raw = await readFile(
    new URL("../app/dashboard-data.json", import.meta.url),
    "utf8",
  );
  const dashboard = JSON.parse(raw);

  assert.equal(dashboard.kpis.sessions, 360129);
  assert.equal(dashboard.kpis.orders, 4436);
  assert.equal(dashboard.funnel.at(-1).sessions, 2491);
  assert.equal(
    dashboard.checkoutTelemetry.find(
      (metric) => metric.key === "purchase_sequence_gap",
    ).numeratorSessions,
    941,
  );
  assert.equal(dashboard.experimentPlan.bufferedTotal, 3296);
  assert.equal(dashboard.simulationOnly.isSimulated, true);

  const serialized = JSON.stringify(dashboard);
  assert.doesNotMatch(
    serialized,
    /user_pseudo_id|ga_session_id|transaction_id|session_key/i,
  );
});
