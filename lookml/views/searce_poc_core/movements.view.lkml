# core.movements — the conformed logistics fact (shared, governed). Measures are
# defined HERE so cost-per-tonne is a weighted SUM(cost)/SUM(tonnes) at ANY
# aggregation level (never an average-of-ratios), and utilisation only averages
# in-range (0–100%) values.

view: movements {
  sql_table_name: `@{gcp_project}.@{ds_core}.movements` ;;

  # ─────────────── Key ───────────────
  dimension: movement_id {
    primary_key: yes
    type: string
    sql: ${TABLE}.movement_id ;;
  }

  # ─────────────── Feed / provider / carrier ───────────────
  dimension: feed          { type: string  sql: ${TABLE}.feed ;; }
  dimension: mode          { type: string  sql: ${TABLE}.mode ;; }
  dimension: provider      { type: string  sql: ${TABLE}.provider ;; }
  dimension: carrier       { type: string  sql: ${TABLE}.carrier ;; }
  dimension: customer      { type: string  sql: ${TABLE}.customer ;; }
  dimension: region        { type: string  sql: ${TABLE}.region ;; }
  dimension: commodity     { type: string  sql: ${TABLE}.commodity ;; }
  dimension: equipment_type { type: string sql: ${TABLE}.equipment_type ;; }

  # ─────────────── Lane / geography ───────────────
  dimension: lane           { type: string sql: ${TABLE}.lane ;; }
  dimension: origin         { type: string sql: ${TABLE}.origin ;; }
  dimension: destination    { type: string sql: ${TABLE}.destination ;; }
  dimension: origin_country { type: string sql: ${TABLE}.origin_country ;; }
  dimension: dest_country   { type: string sql: ${TABLE}.dest_country ;; }
  dimension: trip_type      { type: string sql: ${TABLE}.trip_type ;; }
  dimension: is_international { type: yesno sql: ${TABLE}.is_international ;; }

  # ─────────────── Dates ───────────────
  dimension_group: movement {
    type: time
    timeframes: [raw, date, week, month, quarter, year]
    convert_tz: no
    datatype: date
    sql: ${TABLE}.movement_date ;;
  }
  dimension: financial_period { type: string sql: ${TABLE}.financial_period ;; }

  # ─────────────── Quality flags ───────────────
  dimension: include_flag         { type: yesno sql: ${TABLE}.include_flag ;; }
  dimension: has_cost             { type: yesno sql: ${TABLE}.has_cost ;; }
  dimension: has_tonnes           { type: yesno sql: ${TABLE}.has_tonnes ;; }
  dimension: utilisation_in_range { type: yesno sql: ${TABLE}.utilisation_in_range ;; }

  # ─────────────── Row-level numerics ───────────────
  dimension: tonnes           { type: number sql: ${TABLE}.tonnes ;; value_format_name: decimal_1 }
  dimension: cost_gbp         { type: number sql: ${TABLE}.cost_gbp ;; value_format_name: gbp }
  dimension: finance_cost_gbp { type: number sql: ${TABLE}.finance_cost_gbp ;; value_format_name: gbp }
  dimension: capacity_tonnes  { type: number sql: ${TABLE}.capacity_tonnes ;; value_format_name: decimal_1 }
  dimension: utilisation_pct  { type: number sql: ${TABLE}.utilisation_pct ;; value_format_name: decimal_1 }

  # Utilisation banding for the "where are we paying for air?" tile.
  dimension: utilisation_band {
    type: tier
    tiers: [40, 60, 80, 100]
    style: integer
    sql: ${utilisation_pct} ;;
  }

  # ─────────────── Measures ───────────────
  measure: load_count {
    label: "Loads"
    type: count
    drill_fields: [movement_id, feed, lane, carrier, cost_gbp, tonnes, utilisation_pct]
  }

  measure: total_cost {
    label: "Transport Cost (£)"
    description: "All-in transport cost to TSUK. Ties to source control totals (see Reconciliation)."
    type: sum
    sql: ${cost_gbp} ;;
    value_format_name: gbp
  }

  measure: total_finance_cost {
    label: "Transport Cost — Finance basis (£)"
    description: "Base contracted freight only (excludes fuel surcharge / tolls / handling)."
    type: sum
    sql: ${finance_cost_gbp} ;;
    value_format_name: gbp
  }

  measure: total_tonnes {
    label: "Total Tonnes"
    type: sum
    sql: ${tonnes} ;;
    value_format_name: decimal_0
  }

  measure: transport_cost_per_tonne {
    label: "Transport Cost per Tonne (£) — Logistics basis"
    description: "Logistics basis: all-in transport cost ÷ tonnes moved. Weighted SUM(cost)/SUM(tonnes). This is what Supply Chain calls 'cost per tonne'."
    type: number
    sql: SAFE_DIVIDE(${total_cost}, ${total_tonnes}) ;;
    value_format_name: gbp
  }

  measure: transport_cost_per_tonne_finance {
    label: "Transport Cost per Tonne (£) — Finance basis"
    description: "Finance basis: base contracted freight ÷ tonnes. Sits below the Logistics basis by the fuel/handling/toll surcharges Finance books separately."
    type: number
    sql: SAFE_DIVIDE(${total_finance_cost}, ${total_tonnes}) ;;
    value_format_name: gbp
  }

  measure: cost_per_load {
    label: "Cost per Load (£)"
    type: number
    sql: SAFE_DIVIDE(${total_cost}, ${load_count}) ;;
    value_format_name: gbp
  }

  measure: avg_utilisation {
    label: "Avg Utilisation % (assumed capacity)"
    description: "Averages only in-range (0–100%) values. Capacity is an assumption (see Assumptions)."
    type: average
    sql: ${utilisation_pct} ;;
    filters: [utilisation_in_range: "yes"]
    value_format_name: decimal_1
  }

  measure: loads_under_60 {
    label: "Loads < 60% Utilised"
    type: count
    filters: [utilisation_pct: "<60", utilisation_in_range: "yes"]
  }
}
