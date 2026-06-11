# supplychain.lane_performance — SUPPLY-CHAIN-owned. Lane × month cost/tonne and
# utilisation. Transport cost per tonne here is the Logistics (all-in) basis.

view: lane_performance {
  sql_table_name: `@{gcp_project}.@{ds_supplychain}.lane_performance` ;;

  dimension: pk {
    primary_key: yes
    hidden: yes
    sql: CONCAT(${TABLE}.financial_period, '|', ${TABLE}.feed, '|', ${TABLE}.lane) ;;
  }

  dimension: financial_period { label: "Period" type: string sql: ${TABLE}.financial_period ;; }
  dimension: feed            { type: string sql: ${TABLE}.feed ;; }
  dimension: mode            { type: string sql: ${TABLE}.mode ;; }
  dimension: provider        { type: string sql: ${TABLE}.provider ;; }
  dimension: trip_type       { type: string sql: ${TABLE}.trip_type ;; }
  dimension: lane            { type: string sql: ${TABLE}.lane ;; }
  dimension: origin          { type: string sql: ${TABLE}.origin ;; }
  dimension: destination     { type: string sql: ${TABLE}.destination ;; }
  dimension: commodity       { type: string sql: ${TABLE}.commodity ;; }
  dimension: is_international { type: yesno sql: ${TABLE}.is_international ;; }

  dimension: loads          { type: number sql: ${TABLE}.loads ;; }
  dimension: total_tonnes   { type: number sql: ${TABLE}.total_tonnes ;; value_format_name: decimal_0 }
  dimension: total_cost_gbp { type: number sql: ${TABLE}.total_cost_gbp ;; value_format_name: gbp }

  measure: sum_loads  { label: "Loads" type: sum sql: ${loads} ;; value_format_name: decimal_0 }
  measure: sum_tonnes { label: "Total Tonnes" type: sum sql: ${total_tonnes} ;; value_format_name: decimal_0 }
  measure: sum_cost   { label: "Transport Cost (£)" type: sum sql: ${total_cost_gbp} ;; value_format_name: gbp }

  measure: transport_cost_per_tonne {
    label: "Transport Cost per Tonne (£)"
    description: "Logistics basis: weighted SUM(cost)/SUM(tonnes) across lanes."
    type: number
    sql: SAFE_DIVIDE(${sum_cost}, ${sum_tonnes}) ;;
    value_format_name: gbp
  }
}
