# searce-tsuk-poc — single model over the domain-owned medallion.
# Explores grouped by owner: Governed Core (shared) · Finance · Supply Chain.
# In production each team gets its own model (and optionally connection) so
# access is per-team; for the workshop one model keeps it simple.
#

connection: "sureya-tsuk-logistics"

include: "/views/searce_poc_core/*.view.lkml"
include: "/views/searce_poc_finance/*.view.lkml"
include: "/views/searce_poc_supplychain/*.view.lkml"
include: "/dashboards/*.dashboard.lookml"

# ── Governed core (shared — the contract every team inherits) ──────────────

explore: cost_per_tonne {
  group_label: "Governed Core"
  label: "Cost per Tonne (governed)"
  description: "One source of truth, three legitimate readings: Finance (production), Logistics (transport), Landed (governed = both). By commodity × period."
}

explore: movements {
  group_label: "Governed Core"
  label: "Logistics Movements (conformed fact)"
  description: "One row per movement (rail delivery / road leg / EU shipment). Transport cost, tonnage, utilisation by feed, mode, carrier, lane, trip type."
}

explore: production_cost {
  group_label: "Governed Core"
  label: "Production Cost (conformed fact)"
  description: "Works/manufacturing cost by site × commodity × period — the Finance cost-per-tonne input."
}

explore: reconciliation {
  group_label: "Governed Core"
  label: "Reconciliation (receipts)"
  description: "Per-feed source control total vs computed total. Proves the numbers tie to source (delta £0)."
}

explore: data_catalog {
  group_label: "Governed Core"
  label: "Data Catalog (ownership)"
  description: "Which tables are shared vs team-owned, by layer and owner."
}

# ── Finance-owned ───────────────────────────────────────────────────────────

explore: cost_analysis {
  group_label: "Finance"
  label: "Production Cost Analysis"
  description: "Finance's cost per tonne: works cost by site × commodity × period, with actual-vs-standard variance."
}

explore: management_report {
  group_label: "Finance"
  label: "Management Report"
  description: "Working capital + P&L by period × cost centre × line item, actual vs plan. The Cognos-replacement report."
}

# ── Supply-Chain-owned ──────────────────────────────────────────────────────

explore: lane_performance {
  group_label: "Supply Chain"
  label: "Lane Performance"
  description: "Lane × month transport cost per tonne and utilisation."
}

explore: carrier_spend {
  group_label: "Supply Chain"
  label: "Carrier Spend"
  description: "Carrier × month spend and concentration — the procurement lever."
}

explore: utilisation {
  group_label: "Supply Chain"
  label: "Utilisation"
  description: "Utilisation vs assumed capacity by mode × equipment. Where are we paying to move air?"
}

explore: anomalies {
  group_label: "Supply Chain"
  label: "Cost Leakage (Top-N)"
  description: "Rule-flagged movements ranked by £ impact (cost spikes, zero-tonnage, credits, under/over-utilisation)."
}
