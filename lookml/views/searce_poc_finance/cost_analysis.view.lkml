# finance.cost_analysis — FINANCE-owned. Production cost/tonne by site×commodity×
# period with actual-vs-standard variance. The Finance team's lens on the governed
# cost-per-tonne (finance basis), built from the shared core.production_cost.

view: cost_analysis {
  sql_table_name: `@{gcp_project}.@{ds_finance}.cost_analysis` ;;

  dimension: pk {
    primary_key: yes
    hidden: yes
    sql: CONCAT(${TABLE}.financial_period, '|', ${TABLE}.site, '|', ${TABLE}.commodity) ;;
  }

  dimension: financial_period { label: "Period" type: string sql: ${TABLE}.financial_period ;; }
  dimension: site             { type: string sql: ${TABLE}.site ;; }
  dimension: commodity        { type: string sql: ${TABLE}.commodity ;; }

  dimension: tonnes_produced          { type: number sql: ${TABLE}.tonnes_produced ;; value_format_name: decimal_0 }
  dimension: works_cost_gbp           { type: number sql: ${TABLE}.works_cost_gbp ;; value_format_name: gbp }
  dimension: production_cost_per_tonne { type: number sql: ${TABLE}.production_cost_per_tonne ;; value_format_name: gbp }
  dimension: standard_cost_per_tonne   { type: number sql: ${TABLE}.standard_cost_per_tonne ;; value_format_name: gbp }
  dimension: variance_per_tonne        { type: number sql: ${TABLE}.variance_per_tonne ;; value_format_name: gbp }
  dimension: energy_cost               { type: number sql: ${TABLE}.energy_cost ;; value_format_name: gbp }

  measure: total_works_cost      { label: "Works Cost (£)" type: sum sql: ${works_cost_gbp} ;; value_format_name: gbp }
  measure: total_tonnes_produced { label: "Tonnes Produced" type: sum sql: ${tonnes_produced} ;; value_format_name: decimal_0 }
  measure: total_variance_gbp    { label: "Variance to Standard (£)" type: sum sql: ${TABLE}.variance_gbp ;; value_format_name: gbp }

  measure: production_cost_per_tonne_w {
    label: "Production Cost per Tonne (£)"
    description: "Finance basis: weighted SUM(works cost)/SUM(tonnes produced)."
    type: number
    sql: SAFE_DIVIDE(${total_works_cost}, ${total_tonnes_produced}) ;;
    value_format_name: gbp
  }
}
