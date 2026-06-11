# The receipts: per-feed source control total vs computed total. Delta = £0 proves
# the transformation didn't distort the numbers.

view: reconciliation {
  sql_table_name: `@{gcp_project}.@{ds_core}.reconciliation` ;;

  dimension: feed {
    primary_key: yes
    type: string
    sql: ${TABLE}.feed ;;
  }

  dimension: raw_rows          { label: "Raw Rows" type: number sql: ${TABLE}.raw_rows ;; value_format_name: decimal_0 }
  dimension: movements         { label: "Movements" type: number sql: ${TABLE}.movements ;; value_format_name: decimal_0 }
  dimension: source_cost_gbp   { label: "Source Cost (£)" type: number sql: ${TABLE}.source_cost_gbp ;; value_format_name: gbp }
  dimension: computed_cost_gbp { label: "Computed Cost (£)" type: number sql: ${TABLE}.computed_cost_gbp ;; value_format_name: gbp }
  dimension: cost_delta        { label: "Δ Cost (£)" type: number sql: ${TABLE}.cost_delta ;; value_format_name: gbp }
  dimension: cost_delta_pct    { label: "Δ %" type: number sql: ${TABLE}.cost_delta_pct ;; value_format_name: percent_4 }
  dimension: source_tonnes     { label: "Source Tonnes" type: number sql: ${TABLE}.source_tonnes ;; value_format_name: decimal_0 }
  dimension: computed_tonnes   { label: "Computed Tonnes" type: number sql: ${TABLE}.computed_tonnes ;; value_format_name: decimal_0 }

  measure: total_source_cost   { label: "Σ Source Cost (£)" type: sum sql: ${source_cost_gbp} ;; value_format_name: gbp }
  measure: total_computed_cost { label: "Σ Computed Cost (£)" type: sum sql: ${computed_cost_gbp} ;; value_format_name: gbp }
  measure: total_delta         { label: "Σ Δ (£)" type: sum sql: ${cost_delta} ;; value_format_name: gbp }
}
