# supplychain.carrier_spend — SUPPLY-CHAIN-owned. Carrier × month spend. Surfaces
# carrier concentration — the procurement / negotiation lever.

view: carrier_spend {
  sql_table_name: `@{gcp_project}.@{ds_supplychain}.carrier_spend` ;;

  dimension: pk {
    primary_key: yes
    hidden: yes
    sql: CONCAT(${TABLE}.financial_period, '|', ${TABLE}.feed, '|', ${TABLE}.carrier) ;;
  }

  dimension: financial_period { label: "Period" type: string sql: ${TABLE}.financial_period ;; }
  dimension: feed     { type: string sql: ${TABLE}.feed ;; }
  dimension: mode     { type: string sql: ${TABLE}.mode ;; }
  dimension: provider { type: string sql: ${TABLE}.provider ;; }
  dimension: carrier  { type: string sql: ${TABLE}.carrier ;; }

  dimension: loads          { type: number sql: ${TABLE}.loads ;; }
  dimension: total_tonnes   { type: number sql: ${TABLE}.total_tonnes ;; value_format_name: decimal_0 }
  dimension: total_cost_gbp { type: number sql: ${TABLE}.total_cost_gbp ;; value_format_name: gbp }

  measure: sum_loads  { label: "Loads" type: sum sql: ${loads} ;; value_format_name: decimal_0 }
  measure: sum_tonnes { label: "Total Tonnes" type: sum sql: ${total_tonnes} ;; value_format_name: decimal_0 }
  measure: sum_cost {
    label: "Carrier Spend (£)"
    type: sum
    sql: ${total_cost_gbp} ;;
    value_format_name: gbp
    drill_fields: [carrier, sum_cost, sum_loads, transport_cost_per_tonne]
  }

  measure: transport_cost_per_tonne {
    label: "Transport Cost per Tonne (£)"
    type: number
    sql: SAFE_DIVIDE(${sum_cost}, ${sum_tonnes}) ;;
    value_format_name: gbp
  }
  measure: carrier_count { label: "Distinct Carriers" type: count_distinct sql: ${carrier} ;; }
}
