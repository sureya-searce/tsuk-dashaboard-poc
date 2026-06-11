-- ─────────────────────────────────────────────────────────────────────────
-- CORE data quality & reconciliation — the shared evidence backbone.
--
-- Proves headline numbers tie back to the source files, across BOTH logistics
-- and finance, and surfaces what was excluded and why. Lives in the shared core
-- (every team reads the receipts).
--
--   core.reconciliation : per feed, source control total (straight from source
--                         columns) vs computed total. Delta £0 = no distortion.
--   core.dq_flags       : every excluded / suspect logistics row, with a reason.
--   core.assumptions    : non-source inputs (capacity, provider labels), labelled.
--
-- Called by the Workflow as: CALL `@@PROJECT@@.@@CORE@@.sp_data_quality`()
-- ─────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE `@@PROJECT@@.@@CORE@@.sp_data_quality`()
OPTIONS (strict_mode = false)  -- reads core.* created at runtime
BEGIN

  -- 1. Reconciliation — source control totals vs computed totals ──────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@CORE@@.reconciliation` AS
  WITH raw_control AS (
    SELECT 'rail' AS feed, COUNT(*) AS raw_rows,
      SUM(SAFE_CAST(JSON_VALUE(PARSE_JSON(payload_json), '$.total_excl_cancellation') AS NUMERIC)) AS source_cost_gbp,
      SUM(SAFE_CAST(JSON_VALUE(PARSE_JSON(payload_json), '$.tonnage_tops') AS NUMERIC))             AS source_tonnes
    FROM `@@PROJECT@@.@@RAW@@.raw_rail`
    UNION ALL
    SELECT 'road_uk', COUNT(*),
      SUM(SAFE_CAST(JSON_VALUE(PARSE_JSON(payload_json), '$.purchase_cost') AS NUMERIC)),
      SUM(SAFE_CAST(JSON_VALUE(PARSE_JSON(payload_json), '$.order_weight_t') AS NUMERIC))
    FROM `@@PROJECT@@.@@RAW@@.raw_road_uk`
    UNION ALL
    SELECT 'road_eu', COUNT(*),
      SUM(SAFE_CAST(JSON_VALUE(PARSE_JSON(payload_json), '$.revenue_amount_gbp') AS NUMERIC)),
      CAST(NULL AS NUMERIC)   -- weight repeats per charge line; not summable at raw grain
    FROM `@@PROJECT@@.@@RAW@@.raw_road_eu`
    UNION ALL
    SELECT 'finance_prodcost', COUNT(*),
      SUM(SAFE_CAST(JSON_VALUE(PARSE_JSON(payload_json), '$.works_cost_gbp') AS NUMERIC)),
      SUM(SAFE_CAST(JSON_VALUE(PARSE_JSON(payload_json), '$.tonnes_produced') AS NUMERIC))
    FROM `@@PROJECT@@.@@RAW@@.raw_finance_prodcost`
  ),
  computed AS (
    -- Logistics: from the conformed movements fact.
    SELECT feed, COUNT(*) AS movements, SUM(cost_gbp) AS computed_cost_gbp, SUM(tonnes) AS computed_tonnes
    FROM `@@PROJECT@@.@@CORE@@.movements`
    GROUP BY feed
    UNION ALL
    -- Finance production: from the conformed production fact.
    SELECT 'finance_prodcost', COUNT(*), SUM(works_cost_gbp), SUM(tonnes_produced)
    FROM `@@PROJECT@@.@@CORE@@.production_cost`
  )
  SELECT
    rc.feed,
    rc.raw_rows,
    c.movements,
    rc.source_cost_gbp,
    c.computed_cost_gbp,
    ROUND(c.computed_cost_gbp - rc.source_cost_gbp, 2) AS cost_delta,
    SAFE_DIVIDE(c.computed_cost_gbp - rc.source_cost_gbp, NULLIF(rc.source_cost_gbp, 0)) AS cost_delta_pct,
    rc.source_tonnes,
    c.computed_tonnes,
    CURRENT_TIMESTAMP() AS computed_at
  FROM raw_control rc
  JOIN computed c USING (feed);

  -- 2. DQ flags (logistics) ───────────────────────────────────────────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@CORE@@.dq_flags` AS
  SELECT feed, mode, provider, movement_id, source_file, movement_date, lane,
         tonnes, cost_gbp, utilisation_pct,
         CASE
           -- Negative cost first: has_cost requires cost > 0, so a credit row
           -- would otherwise fall through to MISSING_COST and mislabel.
           WHEN cost_gbp < 0                    THEN 'NEGATIVE_COST'
           WHEN NOT has_cost AND NOT has_tonnes THEN 'NO_COST_NO_TONNAGE'
           WHEN NOT has_tonnes                  THEN 'MISSING_TONNAGE'
           WHEN NOT has_cost                    THEN 'MISSING_COST'
           WHEN NOT has_capacity                THEN 'NO_CAPACITY_LOOKUP'
           WHEN utilisation_pct > 100           THEN 'UTILISATION_OVER_100'
         END AS flag_reason
  FROM `@@PROJECT@@.@@CORE@@.movements`
  WHERE NOT has_cost OR NOT has_tonnes OR NOT has_capacity
     OR utilisation_pct > 100 OR cost_gbp < 0;

  -- 3. Assumptions register ───────────────────────────────────────────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@CORE@@.assumptions` AS
  SELECT
    'capacity' AS assumption_type, feed, equipment_key, capacity_tonnes, basis,
    'Editable in stg.dim_capacity — replace with TSUK fleet spec' AS note
  FROM `@@PROJECT@@.@@STG@@.dim_capacity`
  UNION ALL
  SELECT
    'provider' AS assumption_type, feed_id AS feed, mode AS equipment_key,
    CAST(NULL AS NUMERIC) AS capacity_tonnes, provider AS basis,
    provider_note AS note
  FROM `@@PROJECT@@.@@STG@@.dim_feed`;

END;
