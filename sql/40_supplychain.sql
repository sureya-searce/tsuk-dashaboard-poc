-- ─────────────────────────────────────────────────────────────────────────
-- GOLD supplychain (Supply-Chain-owned) — the team's own views & metrics, all
-- built FROM the shared conformed fact core.movements (read-only to the team).
--
--   supplychain.utilisation      : utilisation vs assumed capacity, by equipment
--   supplychain.lane_performance : lane × month cost/tonne/utilisation
--   supplychain.carrier_spend    : carrier × month spend (concentration lever)
--   supplychain.anomalies        : rule-based cost-leakage (R1-R5), ranked by £ impact
--
-- Transport "cost per tonne" here is the Logistics (all-in) basis — the same
-- definition the governed core.cost_per_tonne exposes; this team view just slices it.
--
-- Called by the Workflow as: CALL `@@PROJECT@@.@@SC@@.sp_build_supplychain`()
-- ─────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE `@@PROJECT@@.@@SC@@.sp_build_supplychain`()
OPTIONS (strict_mode = false)  -- reads core.movements created at runtime
BEGIN

  -- 1. Utilisation by mode × equipment × month ────────────────────────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@SC@@.utilisation` AS
  SELECT
    financial_period, feed, mode, provider, equipment_type,
    COUNT(*)                                                          AS loads,
    AVG(IF(utilisation_pct BETWEEN 0 AND 100, utilisation_pct, NULL)) AS avg_utilisation_pct,
    SUM(IF(utilisation_in_range AND utilisation_pct < 60, 1, 0))      AS loads_under_60pct,
    SUM(IF(utilisation_in_range AND utilisation_pct < 40, 1, 0))      AS loads_under_40pct
  FROM `@@PROJECT@@.@@CORE@@.movements`
  WHERE include_flag
  GROUP BY financial_period, feed, mode, provider, equipment_type;

  -- 2. Lane × month performance ───────────────────────────────────────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@SC@@.lane_performance`
  CLUSTER BY feed AS
  SELECT
    financial_period, feed, mode, provider, trip_type,
    lane, origin, destination, is_international, commodity,
    COUNT(*)                                           AS loads,
    SUM(tonnes)                                        AS total_tonnes,
    SUM(cost_gbp)                                      AS total_cost_gbp,
    SAFE_DIVIDE(SUM(cost_gbp), NULLIF(SUM(tonnes), 0)) AS transport_cost_per_tonne,
    AVG(cost_gbp)                                      AS avg_cost_per_load,
    AVG(IF(utilisation_pct BETWEEN 0 AND 100, utilisation_pct, NULL)) AS avg_utilisation_pct
  FROM `@@PROJECT@@.@@CORE@@.movements`
  WHERE include_flag
  GROUP BY financial_period, feed, mode, provider, trip_type, lane, origin, destination, is_international, commodity;

  -- 3. Carrier × month spend (concentration / negotiation lever) ───────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@SC@@.carrier_spend`
  CLUSTER BY feed AS
  SELECT
    financial_period, feed, mode, provider, carrier,
    COUNT(*)                                           AS loads,
    SUM(tonnes)                                        AS total_tonnes,
    SUM(cost_gbp)                                      AS total_cost_gbp,
    SAFE_DIVIDE(SUM(cost_gbp), NULLIF(SUM(tonnes), 0)) AS transport_cost_per_tonne,
    AVG(IF(utilisation_pct BETWEEN 0 AND 100, utilisation_pct, NULL)) AS avg_utilisation_pct
  FROM `@@PROJECT@@.@@CORE@@.movements`
  WHERE include_flag
  GROUP BY financial_period, feed, mode, provider, carrier;

  -- 4. Cost-leakage anomalies — deterministic SQL, ranked by £ impact ──────
  --    R1 cpt ≥ 1.5× lane median · R2 cost, no tonnage · R3 credit/cancellation
  --    R4 util < 40% · R5 util > 100% (assumption/data error — flag, don't trust)
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@SC@@.anomalies`
  PARTITION BY movement_date
  CLUSTER BY rule_id AS
  WITH m AS (
    SELECT * FROM `@@PROJECT@@.@@CORE@@.movements` WHERE include_flag
  ),
  lane_median AS (
    SELECT lane, APPROX_QUANTILES(cost_per_tonne, 2)[OFFSET(1)] AS median_cpt
    FROM m WHERE has_tonnes AND has_cost
    GROUP BY lane
  ),
  r1 AS (
    SELECT 'R1_COST_PER_TONNE_SPIKE' AS rule_id, 'Cost per tonne ≥ 50% above lane median' AS rule_label,
           m.*, lm.median_cpt AS baseline,
           SAFE_DIVIDE(m.cost_per_tonne - lm.median_cpt, NULLIF(lm.median_cpt, 0)) AS deviation
    FROM m JOIN lane_median lm USING (lane)
    WHERE m.has_tonnes AND m.has_cost AND lm.median_cpt > 0 AND m.cost_per_tonne >= 1.5 * lm.median_cpt
  ),
  r2 AS (
    SELECT 'R2_COST_NO_TONNAGE', 'Cost charged against zero / null tonnage',
           m.*, CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC)
    FROM m WHERE has_cost AND NOT has_tonnes
  ),
  r3 AS (
    SELECT 'R3_CREDIT_OR_CANCELLATION', 'Negative / credit cost (cancellation or rebate)',
           m.*, CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC)
    FROM m WHERE cost_gbp < 0 OR (cancellation_gbp IS NOT NULL AND cancellation_gbp < 0)
  ),
  r4 AS (
    SELECT 'R4_UNDER_UTILISED', 'Load below 40% capacity utilisation',
           m.*, CAST(40 AS NUMERIC), SAFE_DIVIDE(utilisation_pct - 40, 40)
    FROM m WHERE utilisation_in_range AND utilisation_pct < 40 AND has_cost
  ),
  r5 AS (
    SELECT 'R5_UTILISATION_OVER_100', 'Utilisation > 100% — capacity assumption or data error',
           m.*, CAST(100 AS NUMERIC), SAFE_DIVIDE(utilisation_pct - 100, 100)
    FROM m WHERE utilisation_pct > 100
  ),
  unioned AS (
    SELECT * FROM r1 UNION ALL SELECT * FROM r2 UNION ALL SELECT * FROM r3
    UNION ALL SELECT * FROM r4 UNION ALL SELECT * FROM r5
  )
  SELECT
    rule_id, rule_label,
    feed, mode, provider, movement_id, source_file, movement_date, financial_period,
    trip_type, lane, origin, destination, commodity, equipment_type, carrier, customer,
    tonnes, cost_gbp, cost_per_tonne, capacity_tonnes, utilisation_pct,
    baseline, deviation,
    ROUND(ABS(IFNULL(cost_gbp, 0)) * (1 + IFNULL(ABS(deviation), 0)), 2) AS impact_score,
    CURRENT_TIMESTAMP() AS computed_at
  FROM unioned;

END;
