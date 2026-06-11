# Cost-leakage anomalies. A movement can be flagged by more than one rule, so the
# primary key is rule_id + movement_id.

view: anomalies {
  sql_table_name: `@{gcp_project}.@{ds_supplychain}.anomalies` ;;

  dimension: anomaly_key {
    primary_key: yes
    type: string
    sql: CONCAT(${TABLE}.rule_id, '|', ${TABLE}.movement_id) ;;
  }

  dimension: rule_id     { type: string sql: ${TABLE}.rule_id ;; }
  dimension: rule_label  { label: "Rule" type: string sql: ${TABLE}.rule_label ;; }
  dimension: movement_id { type: string sql: ${TABLE}.movement_id ;; }
  dimension: feed        { type: string sql: ${TABLE}.feed ;; }
  dimension: mode        { type: string sql: ${TABLE}.mode ;; }
  dimension: provider    { type: string sql: ${TABLE}.provider ;; }
  dimension: trip_type   { type: string sql: ${TABLE}.trip_type ;; }
  dimension: lane        { type: string sql: ${TABLE}.lane ;; }
  dimension: carrier     { type: string sql: ${TABLE}.carrier ;; }
  dimension: customer    { type: string sql: ${TABLE}.customer ;; }
  dimension: commodity   { type: string sql: ${TABLE}.commodity ;; }
  dimension: equipment_type { type: string sql: ${TABLE}.equipment_type ;; }
  dimension: source_file { type: string sql: ${TABLE}.source_file ;; }

  dimension_group: movement {
    type: time
    timeframes: [raw, date, month, quarter]
    convert_tz: no
    datatype: date
    sql: ${TABLE}.movement_date ;;
  }

  dimension: tonnes          { type: number sql: ${TABLE}.tonnes ;; value_format_name: decimal_1 }
  dimension: cost_gbp        { type: number sql: ${TABLE}.cost_gbp ;; value_format_name: gbp }
  dimension: cost_per_tonne  { type: number sql: ${TABLE}.cost_per_tonne ;; value_format_name: gbp }
  dimension: utilisation_pct { type: number sql: ${TABLE}.utilisation_pct ;; value_format_name: decimal_1 }
  dimension: baseline        { type: number sql: ${TABLE}.baseline ;; }
  dimension: deviation       { type: number sql: ${TABLE}.deviation ;; value_format_name: percent_1 }
  dimension: impact_score    { label: "Impact (£)" type: number sql: ${TABLE}.impact_score ;; value_format_name: gbp }

  measure: anomaly_count { label: "Anomalies" type: count }
  measure: total_impact {
    label: "Total Impact (£)"
    type: sum
    sql: ${impact_score} ;;
    value_format_name: gbp
  }
  measure: total_exposed_cost {
    label: "Exposed Cost (£)"
    type: sum
    sql: ${cost_gbp} ;;
    value_format_name: gbp
  }
}
