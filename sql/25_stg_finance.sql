-- ─────────────────────────────────────────────────────────────────────────
-- STG finance (silver, shared conformed) — clean/typed finance source rows.
--
-- Mirrors sp_normalise for logistics: raw JSON → typed, conformed columns, with
-- the SAME period/commodity/site keys the conformed dimensions use, so finance
-- lines up with logistics for cross-team KPIs. No business KPI logic here — that
-- lives in the gold layer (core + team marts).
--
--   stg.production : works/production cost (site × commodity × period)
--   stg.management : management report — working capital + P&L (period × cost centre × line item)
--
-- Called by the Workflow as: CALL `@@PROJECT@@.@@STG@@.sp_finance_stage`()
-- ─────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE `@@PROJECT@@.@@STG@@.sp_finance_stage`()
OPTIONS (strict_mode = false)
BEGIN

  -- ── Production cost (Finance's "cost per tonne" input) ──────────────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@STG@@.production` AS
  WITH src AS (
    SELECT source_file, PARSE_JSON(payload_json) AS j
    FROM `@@PROJECT@@.@@RAW@@.raw_finance_prodcost`
  )
  SELECT
    source_file,
    JSON_VALUE(j, '$.period')                                       AS financial_period,
    INITCAP(TRIM(JSON_VALUE(j, '$.site')))                          AS site,
    INITCAP(LOWER(TRIM(JSON_VALUE(j, '$.commodity'))))              AS commodity,
    SAFE_CAST(JSON_VALUE(j, '$.tonnes_produced') AS NUMERIC)        AS tonnes_produced,
    SAFE_CAST(JSON_VALUE(j, '$.works_cost_gbp') AS NUMERIC)         AS works_cost_gbp,
    SAFE_CAST(JSON_VALUE(j, '$.raw_material_cost') AS NUMERIC)      AS raw_material_cost,
    SAFE_CAST(JSON_VALUE(j, '$.energy_cost') AS NUMERIC)            AS energy_cost,
    SAFE_CAST(JSON_VALUE(j, '$.labour_cost') AS NUMERIC)            AS labour_cost,
    SAFE_CAST(JSON_VALUE(j, '$.overhead_cost') AS NUMERIC)          AS overhead_cost,
    SAFE_CAST(JSON_VALUE(j, '$.standard_cost_per_tonne') AS NUMERIC) AS standard_cost_per_tonne
  FROM src
  WHERE JSON_VALUE(j, '$.period') IS NOT NULL;

  -- ── Management report (working capital + P&L) ───────────────────────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@STG@@.management` AS
  WITH src AS (
    SELECT source_file, PARSE_JSON(payload_json) AS j
    FROM `@@PROJECT@@.@@RAW@@.raw_finance_mgmt`
  )
  SELECT
    source_file,
    JSON_VALUE(j, '$.period')                                AS financial_period,
    TRIM(JSON_VALUE(j, '$.cost_centre'))                     AS cost_centre,
    TRIM(JSON_VALUE(j, '$.line_item'))                       AS line_item,
    TRIM(JSON_VALUE(j, '$.category'))                        AS category,
    SAFE_CAST(JSON_VALUE(j, '$.amount_gbp') AS NUMERIC)      AS amount_gbp,
    SAFE_CAST(JSON_VALUE(j, '$.plan_amount_gbp') AS NUMERIC) AS plan_amount_gbp
  FROM src
  WHERE JSON_VALUE(j, '$.period') IS NOT NULL;

END;
