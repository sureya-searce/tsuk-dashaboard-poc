# core.data_catalog — the ownership registry. Makes shared-vs-team-owned explicit
# and inspectable (which tables a team owns vs reads). Backs the governance story.

view: data_catalog {
  sql_table_name: `@{gcp_project}.@{ds_core}.data_catalog` ;;

  dimension: pk {
    primary_key: yes
    hidden: yes
    sql: CONCAT(${TABLE}.layer, '|', ${TABLE}.object) ;;
  }

  dimension: layer  { label: "Layer" type: string sql: ${TABLE}.layer ;; }
  dimension: owner  { label: "Owner" type: string sql: ${TABLE}.owner ;; }
  dimension: object { label: "Object" type: string sql: ${TABLE}.object ;; }
  dimension: grain  { label: "Grain / purpose" type: string sql: ${TABLE}.grain ;; }
  dimension: is_shared {
    label: "Shared?"
    type: yesno
    sql: ${TABLE}.owner = 'shared' ;;
  }

  measure: object_count { label: "Objects" type: count }
}
