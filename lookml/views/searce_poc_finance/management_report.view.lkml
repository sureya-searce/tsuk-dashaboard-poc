# finance.management_report — FINANCE-owned. Working capital + P&L by period ×
# cost-centre × line-item, actual vs plan. The Cognos-replacement report built on
# the semantic layer.

view: management_report {
  sql_table_name: `@{gcp_project}.@{ds_finance}.management_report` ;;

  dimension: pk {
    primary_key: yes
    hidden: yes
    sql: CONCAT(${TABLE}.financial_period, '|', ${TABLE}.cost_centre, '|', ${TABLE}.line_item) ;;
  }

  dimension: financial_period { label: "Period" type: string sql: ${TABLE}.financial_period ;; }
  dimension: cost_centre      { label: "Cost Centre" type: string sql: ${TABLE}.cost_centre ;; }
  dimension: line_item        { label: "Line Item" type: string sql: ${TABLE}.line_item ;; }
  dimension: category         { label: "Category" type: string sql: ${TABLE}.category ;; }

  dimension: amount_gbp      { label: "Amount (£)" type: number sql: ${TABLE}.amount_gbp ;; value_format_name: gbp }
  dimension: plan_amount_gbp { label: "Plan (£)" type: number sql: ${TABLE}.plan_amount_gbp ;; value_format_name: gbp }
  dimension: variance_gbp    { label: "Variance (£)" type: number sql: ${TABLE}.variance_gbp ;; value_format_name: gbp }
  dimension: variance_pct    { label: "Variance %" type: number sql: ${TABLE}.variance_pct ;; value_format_name: percent_1 }

  measure: total_amount {
    label: "Amount (£)"
    type: sum
    sql: ${amount_gbp} ;;
    value_format_name: gbp
  }
  measure: total_plan {
    label: "Plan (£)"
    type: sum
    sql: ${plan_amount_gbp} ;;
    value_format_name: gbp
  }
  measure: total_variance {
    label: "Variance to Plan (£)"
    type: sum
    sql: ${variance_gbp} ;;
    value_format_name: gbp
  }

  # Working capital = Inventory + Receivables − Payables (Payables stored negative).
  measure: working_capital {
    label: "Working Capital (£)"
    description: "Inventory + Trade Receivables − Trade Payables (Working Capital line items only)."
    type: sum
    sql: ${amount_gbp} ;;
    filters: [category: "Working Capital"]
    value_format_name: gbp
  }
}
