# TSUK Finance dashboard (Richard Williams persona).
# LookML dashboards are read-only in the UI — for the live "add a widget" demo
# beat, copy this dashboard to a user-defined one (More → Copy) and add there.

- dashboard: tsuk_finance
  title: "TSUK Finance — Production Cost & Management"
  layout: newspaper
  preferred_viewer: dashboards-next

  filters:
  - name: Commodity
    title: "Commodity"
    type: field_filter
    model: searce-tsuk-poc
    explore: cost_analysis
    field: cost_analysis.commodity
    allow_multiple_values: true
    required: false

  elements:

  # ── Row 0: headline KPIs ──────────────────────────────────────────────
  - name: kpi_production_cpt
    title: "Production Cost per Tonne (Finance basis)"
    model: searce-tsuk-poc
    explore: cost_analysis
    type: single_value
    fields: [cost_analysis.production_cost_per_tonne_w]
    listen:
      Commodity: cost_analysis.commodity
    row: 0
    col: 0
    width: 8
    height: 4

  - name: kpi_works_cost
    title: "Total Works Cost (FY26)"
    model: searce-tsuk-poc
    explore: cost_analysis
    type: single_value
    fields: [cost_analysis.total_works_cost]
    listen:
      Commodity: cost_analysis.commodity
    row: 0
    col: 8
    width: 8
    height: 4

  - name: kpi_working_capital
    title: "Working Capital (actual)"
    model: searce-tsuk-poc
    explore: management_report
    type: single_value
    fields: [management_report.working_capital]
    row: 0
    col: 16
    width: 8
    height: 4

  # ── Row 1: production cost lens ──────────────────────────────────────
  - name: cpt_by_commodity
    title: "Production Cost per Tonne by Commodity"
    model: searce-tsuk-poc
    explore: cost_analysis
    type: looker_column
    fields: [cost_analysis.commodity, cost_analysis.production_cost_per_tonne_w]
    sorts: [cost_analysis.production_cost_per_tonne_w desc]
    listen:
      Commodity: cost_analysis.commodity
    row: 4
    col: 0
    width: 12
    height: 7

  - name: variance_by_site
    title: "Variance to Standard by Site (£)"
    model: searce-tsuk-poc
    explore: cost_analysis
    type: looker_bar
    fields: [cost_analysis.site, cost_analysis.total_variance_gbp]
    sorts: [cost_analysis.total_variance_gbp desc]
    listen:
      Commodity: cost_analysis.commodity
    row: 4
    col: 12
    width: 12
    height: 7

  # ── Row 2: management report lens ────────────────────────────────────
  - name: wc_vs_plan
    title: "Working Capital — Actual vs Plan by Cost Centre"
    model: searce-tsuk-poc
    explore: management_report
    type: looker_column
    fields: [management_report.cost_centre, management_report.total_amount, management_report.total_plan]
    filters:
      management_report.category: "Working Capital"
    sorts: [management_report.total_amount desc]
    row: 11
    col: 0
    width: 12
    height: 7

  - name: energy_trend
    title: "Energy Cost by Period"
    model: searce-tsuk-poc
    explore: production_cost
    type: looker_line
    fields: [production_cost.financial_period, production_cost.total_energy_cost]
    sorts: [production_cost.financial_period]
    listen:
      Commodity: production_cost.commodity
    row: 11
    col: 12
    width: 12
    height: 7
