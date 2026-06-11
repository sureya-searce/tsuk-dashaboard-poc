# TSUK Supply Chain dashboard (Dan Jones persona).
# LookML dashboards are read-only in the UI — for the live "add a widget" demo
# beat, copy this dashboard to a user-defined one (More → Copy) and add there.

- dashboard: tsuk_supplychain
  title: "TSUK Supply Chain — Transport Cost & Utilisation"
  layout: newspaper
  preferred_viewer: dashboards-next

  filters:
  - name: Feed
    title: "Feed"
    type: field_filter
    model: searce-tsuk-poc
    explore: movements
    field: movements.feed
    allow_multiple_values: true
    required: false

  elements:

  # ── Row 0: headline KPIs ──────────────────────────────────────────────
  - name: kpi_transport_cpt
    title: "Transport Cost per Tonne (Logistics basis)"
    model: searce-tsuk-poc
    explore: movements
    type: single_value
    fields: [movements.transport_cost_per_tonne]
    listen:
      Feed: movements.feed
    row: 0
    col: 0
    width: 6
    height: 4

  - name: kpi_total_cost
    title: "Total Transport Cost"
    model: searce-tsuk-poc
    explore: movements
    type: single_value
    fields: [movements.total_cost]
    listen:
      Feed: movements.feed
    row: 0
    col: 6
    width: 6
    height: 4

  - name: kpi_loads
    title: "Loads"
    model: searce-tsuk-poc
    explore: movements
    type: single_value
    fields: [movements.load_count]
    listen:
      Feed: movements.feed
    row: 0
    col: 12
    width: 6
    height: 4

  - name: kpi_under60
    title: "Loads < 60% Utilised"
    model: searce-tsuk-poc
    explore: movements
    type: single_value
    fields: [movements.loads_under_60]
    listen:
      Feed: movements.feed
    row: 0
    col: 18
    width: 6
    height: 4

  # ── Row 1: cost + utilisation lens ───────────────────────────────────
  - name: cpt_by_feed
    title: "Transport Cost per Tonne by Feed"
    model: searce-tsuk-poc
    explore: movements
    type: looker_column
    fields: [movements.feed, movements.transport_cost_per_tonne]
    sorts: [movements.transport_cost_per_tonne desc]
    listen:
      Feed: movements.feed
    row: 4
    col: 0
    width: 12
    height: 7

  - name: util_by_equipment
    title: "Avg Utilisation by Equipment (assumed capacity)"
    model: searce-tsuk-poc
    explore: utilisation
    type: looker_bar
    fields: [utilisation.equipment_type, utilisation.avg_utilisation]
    sorts: [utilisation.avg_utilisation]
    listen:
      Feed: utilisation.feed
    row: 4
    col: 12
    width: 12
    height: 7

  # ── Row 2: carriers + cost leakage ───────────────────────────────────
  - name: carrier_concentration
    title: "Carrier Spend — Top 10 (concentration lever)"
    model: searce-tsuk-poc
    explore: carrier_spend
    type: looker_bar
    fields: [carrier_spend.carrier, carrier_spend.sum_cost]
    sorts: [carrier_spend.sum_cost desc]
    limit: 10
    listen:
      Feed: carrier_spend.feed
    row: 11
    col: 0
    width: 12
    height: 7

  - name: cost_leakage_top10
    title: "Cost Leakage — Top 10 by £ Impact"
    model: searce-tsuk-poc
    explore: anomalies
    type: looker_grid
    fields: [anomalies.rule_label, anomalies.feed, anomalies.lane, anomalies.carrier, anomalies.cost_gbp, anomalies.utilisation_pct, anomalies.impact_score]
    sorts: [anomalies.impact_score desc]
    limit: 10
    listen:
      Feed: anomalies.feed
    row: 11
    col: 12
    width: 12
    height: 7
