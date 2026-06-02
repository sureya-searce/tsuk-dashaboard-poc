-- ─────────────────────────────────────────────────────────────────────────
-- MART anomalies — rule-based cost-leakage detection. DETERMINISTIC SQL only;
-- no ML, no LLM. Every anomaly is a real movement row with real values, ranked
-- by £ impact. This powers the Top-10 digest tile.
--
-- Rules:
--   R1  Cost per tonne ≥ 50% above the lane's median (cost spike on a lane)
--   R2  Cost charged against zero/again null tonnage (paying for nothing)
--   R3  Negative / credit cost lines (cancellations, rebates) by magnitude
--   R4  Structural under-utilisation: load < 40% of capacity (paying to move air)
--   R5  Utilisation > 100%: capacity-assumption or data error (flag, don't trust)
--
-- Called by the Workflow as: CALL `@@PROJECT@@.@@MART@@.sp_anomalies`()
-- ─────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE `@@PROJECT@@.@@MART@@.sp_anomalies`()
OPTIONS (strict_mode = false)  -- reads mart.movements, created at runtime by sp_unify
BEGIN

  CREATE OR REPLACE TABLE `@@PROJECT@@.@@MART@@.anomalies`
  PARTITION BY movement_date
  CLUSTER BY rule_id AS

  WITH m AS (
    SELECT * FROM `@@PROJECT@@.@@MART@@.movements` WHERE include_flag
  ),
  lane_median AS (
    SELECT lane,
           APPROX_QUANTILES(cost_per_tonne, 2)[OFFSET(1)] AS median_cpt
    FROM m
    WHERE has_tonnes AND has_cost
    GROUP BY lane
  ),

  -- R1: cost-per-tonne spike vs lane median
  r1 AS (
    SELECT
      'R1_COST_PER_TONNE_SPIKE' AS rule_id,
      'Cost per tonne ≥ 50% above lane median' AS rule_label,
      m.*,
      lm.median_cpt AS baseline,
      SAFE_DIVIDE(m.cost_per_tonne - lm.median_cpt, NULLIF(lm.median_cpt, 0)) AS deviation
    FROM m JOIN lane_median lm USING (lane)
    WHERE m.has_tonnes AND m.has_cost
      AND lm.median_cpt > 0
      AND m.cost_per_tonne >= 1.5 * lm.median_cpt
  ),

  -- R2: cost with no tonnage
  r2 AS (
    SELECT
      'R2_COST_NO_TONNAGE' AS rule_id,
      'Cost charged against zero / null tonnage' AS rule_label,
      m.*,
      CAST(NULL AS NUMERIC) AS baseline,
      CAST(NULL AS NUMERIC) AS deviation
    FROM m
    WHERE has_cost AND NOT has_tonnes
  ),

  -- R3: negative / credit lines
  r3 AS (
    SELECT
      'R3_CREDIT_OR_CANCELLATION' AS rule_id,
      'Negative / credit cost (cancellation or rebate)' AS rule_label,
      m.*,
      CAST(NULL AS NUMERIC) AS baseline,
      CAST(NULL AS NUMERIC) AS deviation
    FROM m
    WHERE cost_gbp < 0 OR (cancellation_gbp IS NOT NULL AND cancellation_gbp < 0)
  ),

  -- R4: structural under-utilisation
  r4 AS (
    SELECT
      'R4_UNDER_UTILISED' AS rule_id,
      'Load below 40% capacity utilisation' AS rule_label,
      m.*,
      CAST(40 AS NUMERIC) AS baseline,
      SAFE_DIVIDE(utilisation_pct - 40, 40) AS deviation
    FROM m
    WHERE utilisation_in_range AND utilisation_pct < 40 AND has_cost
  ),

  -- R5: utilisation > 100% (assumption / data error — flag, do not trust)
  r5 AS (
    SELECT
      'R5_UTILISATION_OVER_100' AS rule_id,
      'Utilisation > 100% — capacity assumption or data error' AS rule_label,
      m.*,
      CAST(100 AS NUMERIC) AS baseline,
      SAFE_DIVIDE(utilisation_pct - 100, 100) AS deviation
    FROM m
    WHERE utilisation_pct > 100
  ),

  unioned AS (
    SELECT * FROM r1 UNION ALL
    SELECT * FROM r2 UNION ALL
    SELECT * FROM r3 UNION ALL
    SELECT * FROM r4 UNION ALL
    SELECT * FROM r5
  )

  SELECT
    rule_id,
    rule_label,
    feed, mode, provider, movement_id, source_file, movement_date, financial_period,
    trip_type, lane, origin, destination, commodity, equipment_type, carrier, customer,
    tonnes, cost_gbp, cost_per_tonne, capacity_tonnes, utilisation_pct,
    baseline, deviation,
    -- Impact score: absolute GBP exposure, amplified by deviation magnitude.
    ROUND(ABS(IFNULL(cost_gbp, 0)) * (1 + IFNULL(ABS(deviation), 0)), 2) AS impact_score,
    CURRENT_TIMESTAMP() AS computed_at
  FROM unioned;

END;
