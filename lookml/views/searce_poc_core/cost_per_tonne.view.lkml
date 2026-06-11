# core.cost_per_tonne — THE governed cross-team KPI, defined once and inherited by
# every team model and by Conversational Analytics. One row per commodity × period.
#
# "Cost per tonne" legitimately means three things from the SAME source of truth:
#   - Finance basis    = production / works cost ÷ tonnes produced
#   - Logistics basis  = all-in transport cost ÷ tonnes moved
#   - Landed (GOVERNED)= production + transport, signed off across functions
# The rich descriptions below are what the AI grounds on — so it answers the
# ambiguous "what's our cost per tonne?" with the governed definition, not a guess.

view: cost_per_tonne {
  sql_table_name: `@{gcp_project}.@{ds_core}.cost_per_tonne` ;;

  dimension: pk {
    primary_key: yes
    hidden: yes
    sql: CONCAT(${TABLE}.financial_period, '|', ${TABLE}.commodity) ;;
  }

  dimension: financial_period { label: "Period" type: string sql: ${TABLE}.financial_period ;; }
  dimension: commodity        { type: string sql: ${TABLE}.commodity ;; }

  # Row-level (already per commodity×period) cost-per-tonne readings.
  dimension: production_cost_per_tonne {
    label: "Production £/t (Finance basis)"
    description: "Finance's cost per tonne: works/manufacturing cost ÷ tonnes produced."
    type: number
    sql: ${TABLE}.production_cost_per_tonne ;;
    value_format_name: gbp
  }
  dimension: transport_cost_per_tonne {
    label: "Transport £/t (Logistics basis)"
    description: "Logistics' cost per tonne: all-in transport cost ÷ tonnes moved."
    type: number
    sql: ${TABLE}.transport_cost_per_tonne ;;
    value_format_name: gbp
  }
  dimension: landed_cost_per_tonne {
    label: "Landed £/t (Governed)"
    description: "The org-agreed cost per tonne = production + transport."
    type: number
    sql: ${TABLE}.landed_cost_per_tonne ;;
    value_format_name: gbp
  }

  dimension: production_cost_gbp { type: number sql: ${TABLE}.production_cost_gbp ;; value_format_name: gbp }
  dimension: transport_cost_gbp  { type: number sql: ${TABLE}.transport_cost_gbp ;; value_format_name: gbp }
  dimension: tonnes_produced     { type: number sql: ${TABLE}.tonnes_produced ;; value_format_name: decimal_0 }
  dimension: tonnes_moved        { type: number sql: ${TABLE}.tonnes_moved ;; value_format_name: decimal_0 }

  # ── Governed measures (weighted, valid at any aggregation) ──────────────
  measure: total_production_cost { type: sum sql: ${production_cost_gbp} ;; value_format_name: gbp }
  measure: total_transport_cost  { type: sum sql: ${transport_cost_gbp} ;; value_format_name: gbp }
  measure: total_tonnes_produced { type: sum sql: ${tonnes_produced} ;; value_format_name: decimal_0 }
  measure: total_tonnes_moved    { type: sum sql: ${tonnes_moved} ;; value_format_name: decimal_0 }

  measure: cost_per_tonne_finance {
    label: "Cost per Tonne — Finance basis (£)"
    description: "Finance's definition: production/works cost ÷ tonnes produced. Weighted SUM/SUM."
    type: number
    sql: SAFE_DIVIDE(${total_production_cost}, ${total_tonnes_produced}) ;;
    value_format_name: gbp
  }
  measure: cost_per_tonne_logistics {
    label: "Cost per Tonne — Logistics basis (£)"
    description: "Logistics' definition: all-in transport cost ÷ tonnes moved. Weighted SUM/SUM."
    type: number
    sql: SAFE_DIVIDE(${total_transport_cost}, ${total_tonnes_moved}) ;;
    value_format_name: gbp
  }
  measure: cost_per_tonne_landed {
    label: "Cost per Tonne — Landed (GOVERNED) (£)"
    description: "The single org-agreed cost per tonne = Finance basis + Logistics basis. This is the definition dashboards and AI agents inherit. Use this when asked for 'cost per tonne' without qualification."
    type: number
    sql: ${cost_per_tonne_finance} + ${cost_per_tonne_logistics} ;;
    value_format_name: gbp
  }
  measure: finance_vs_logistics_gap_pct {
    label: "Finance vs Logistics gap (%)"
    description: "How far the two teams' 'cost per tonne' diverge — the reason a shared definition matters."
    type: number
    sql: SAFE_DIVIDE(${cost_per_tonne_logistics} - ${cost_per_tonne_finance}, NULLIF(${cost_per_tonne_finance}, 0)) ;;
    value_format_name: percent_1
  }
}
