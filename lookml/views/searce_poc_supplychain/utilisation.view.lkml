# supplychain.utilisation — SUPPLY-CHAIN-owned. Utilisation vs assumed capacity by
# mode × equipment × period. "Where are we paying to move air?"

view: utilisation {
  sql_table_name: `@{gcp_project}.@{ds_supplychain}.utilisation` ;;

  dimension: pk {
    primary_key: yes
    hidden: yes
    sql: CONCAT(${TABLE}.financial_period, '|', ${TABLE}.feed, '|', ${TABLE}.equipment_type) ;;
  }

  dimension: financial_period { label: "Period" type: string sql: ${TABLE}.financial_period ;; }
  dimension: feed           { type: string sql: ${TABLE}.feed ;; }
  dimension: mode           { type: string sql: ${TABLE}.mode ;; }
  dimension: provider       { type: string sql: ${TABLE}.provider ;; }
  dimension: equipment_type { type: string sql: ${TABLE}.equipment_type ;; }

  dimension: avg_utilisation_pct { type: number sql: ${TABLE}.avg_utilisation_pct ;; value_format_name: decimal_1 }
  dimension: loads               { type: number sql: ${TABLE}.loads ;; }
  dimension: loads_under_60pct   { type: number sql: ${TABLE}.loads_under_60pct ;; }
  dimension: loads_under_40pct   { type: number sql: ${TABLE}.loads_under_40pct ;; }

  measure: total_loads        { label: "Loads" type: sum sql: ${loads} ;; value_format_name: decimal_0 }
  measure: total_under_60      { label: "Loads < 60% Utilised" type: sum sql: ${loads_under_60pct} ;; value_format_name: decimal_0 }
  measure: total_under_40      { label: "Loads < 40% Utilised" type: sum sql: ${loads_under_40pct} ;; value_format_name: decimal_0 }
  measure: avg_utilisation {
    label: "Avg Utilisation % (assumed capacity)"
    description: "Mean utilisation across the rolled-up groups. Capacity is an assumption."
    type: average
    sql: ${avg_utilisation_pct} ;;
    value_format_name: decimal_1
  }
}
