# core.production_cost — conformed finance production fact (shared). One row per
# site × commodity × period. Finance's "cost per tonne" originates here.

view: production_cost {
  sql_table_name: `@{gcp_project}.@{ds_core}.production_cost` ;;

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
  dimension: raw_material_cost        { type: number sql: ${TABLE}.raw_material_cost ;; value_format_name: gbp }
  dimension: energy_cost              { type: number sql: ${TABLE}.energy_cost ;; value_format_name: gbp }
  dimension: labour_cost              { type: number sql: ${TABLE}.labour_cost ;; value_format_name: gbp }
  dimension: overhead_cost            { type: number sql: ${TABLE}.overhead_cost ;; value_format_name: gbp }
  dimension: standard_cost_per_tonne  { type: number sql: ${TABLE}.standard_cost_per_tonne ;; value_format_name: gbp }
  dimension: production_cost_per_tonne { type: number sql: ${TABLE}.production_cost_per_tonne ;; value_format_name: gbp }

  measure: total_works_cost { label: "Works Cost (£)" type: sum sql: ${works_cost_gbp} ;; value_format_name: gbp }
  measure: total_tonnes_produced { label: "Tonnes Produced" type: sum sql: ${tonnes_produced} ;; value_format_name: decimal_0 }
  measure: total_energy_cost { label: "Energy Cost (£)" type: sum sql: ${energy_cost} ;; value_format_name: gbp }

  measure: production_cost_per_tonne_w {
    label: "Production Cost per Tonne (£)"
    description: "Finance basis. Weighted SUM(works cost)/SUM(tonnes produced)."
    type: number
    sql: SAFE_DIVIDE(${total_works_cost}, ${total_tonnes_produced}) ;;
    value_format_name: gbp
  }
}
