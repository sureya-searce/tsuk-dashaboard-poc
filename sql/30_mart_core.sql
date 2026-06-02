-- ─────────────────────────────────────────────────────────────────────────
-- MART core — single source of truth fact table + supporting rollups.
--
-- mart_movements is THE fact (one row per movement/trip). Every dashboard tile
-- and every Conversational Analytics answer aggregates THIS table via the
-- LookML semantic layer. No number is computed anywhere else. Full lineage and
-- the provider / mode / carrier / trip_type dimensions live here.
--
-- Called by the Workflow as: CALL `@@PROJECT@@.@@MART@@.sp_unify`()
-- ─────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE `@@PROJECT@@.@@MART@@.sp_unify`()
OPTIONS (strict_mode = false)  -- reads stg.shipments, created at runtime by sp_normalise
BEGIN

  -- 1. Fact table ─────────────────────────────────────────────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@MART@@.movements`
  PARTITION BY movement_date
  CLUSTER BY feed, lane AS
  SELECT
    *,
    (tonnes > 0)                              AS has_tonnes,
    (cost_gbp IS NOT NULL AND cost_gbp > 0)   AS has_cost,
    (capacity_tonnes > 0)                     AS has_capacity,
    (utilisation_pct IS NOT NULL
       AND utilisation_pct BETWEEN 0 AND 100) AS utilisation_in_range
  FROM `@@PROJECT@@.@@STG@@.shipments`;

  -- 2. Lane × month rollup ────────────────────────────────────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@MART@@.lane_monthly`
  CLUSTER BY feed AS
  SELECT
    financial_period, feed, mode, provider, trip_type,
    lane, origin, destination, is_international,
    COUNT(*)                                   AS loads,
    SUM(tonnes)                                AS total_tonnes,
    SUM(cost_gbp)                              AS total_cost_gbp,
    SAFE_DIVIDE(SUM(cost_gbp), NULLIF(SUM(tonnes), 0)) AS cost_per_tonne,
    AVG(cost_gbp)                              AS avg_cost_per_load,
    AVG(IF(utilisation_pct BETWEEN 0 AND 100, utilisation_pct, NULL)) AS avg_utilisation_pct
  FROM `@@PROJECT@@.@@MART@@.movements`
  WHERE include_flag
  GROUP BY financial_period, feed, mode, provider, trip_type, lane, origin, destination, is_international;

  -- 3. Carrier × month rollup — "cost by carrier/provider" ────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@MART@@.carrier_monthly`
  CLUSTER BY feed AS
  SELECT
    financial_period, feed, mode, provider, carrier,
    COUNT(*)                                   AS loads,
    SUM(tonnes)                                AS total_tonnes,
    SUM(cost_gbp)                              AS total_cost_gbp,
    SAFE_DIVIDE(SUM(cost_gbp), NULLIF(SUM(tonnes), 0)) AS cost_per_tonne,
    AVG(IF(utilisation_pct BETWEEN 0 AND 100, utilisation_pct, NULL)) AS avg_utilisation_pct
  FROM `@@PROJECT@@.@@MART@@.movements`
  WHERE include_flag
  GROUP BY financial_period, feed, mode, provider, carrier;

  -- 4. Headline KPI by month × feed × mode (top dashboard tiles) ───
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@MART@@.kpi_monthly` AS
  SELECT
    financial_period, feed, mode, provider, trip_type,
    COUNT(*)                                   AS loads,
    SUM(tonnes)                                AS total_tonnes,
    SUM(cost_gbp)                              AS total_cost_gbp,
    SAFE_DIVIDE(SUM(cost_gbp), NULLIF(SUM(tonnes), 0)) AS cost_per_tonne,
    SAFE_DIVIDE(SUM(cost_gbp), NULLIF(COUNT(*), 0))    AS cost_per_load,
    AVG(IF(utilisation_pct BETWEEN 0 AND 100, utilisation_pct, NULL)) AS avg_utilisation_pct,
    SUM(IF(utilisation_pct < 60, 1, 0))        AS loads_under_60pct_util
  FROM `@@PROJECT@@.@@MART@@.movements`
  WHERE include_flag
  GROUP BY financial_period, feed, mode, provider, trip_type;

END;
