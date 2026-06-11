-- ─────────────────────────────────────────────────────────────────────────
-- GOLD finance (Finance-owned) — the team's own views & metrics, built FROM the
-- shared conformed facts (core.production_cost, stg.management; read-only to the team).
--
--   finance.cost_analysis     : production cost/tonne by site×commodity×period,
--                               with actual-vs-standard variance. The Finance lens
--                               on the governed core.cost_per_tonne (finance basis).
--   finance.management_report : working capital + P&L by period×cost-centre×line-item,
--                               actual vs plan — the Cognos-replacement report.
--
-- Called by the Workflow as: CALL `@@PROJECT@@.@@FINANCE@@.sp_build_finance`()
-- ─────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE `@@PROJECT@@.@@FINANCE@@.sp_build_finance`()
OPTIONS (strict_mode = false)  -- reads core.production_cost / stg.management at runtime
BEGIN

  -- 1. Production cost analysis (Finance's "cost per tonne") ───────────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@FINANCE@@.cost_analysis` AS
  SELECT
    financial_period,
    site,
    commodity,
    tonnes_produced,
    works_cost_gbp,
    production_cost_per_tonne,
    standard_cost_per_tonne,
    ROUND(production_cost_per_tonne - standard_cost_per_tonne, 2)        AS variance_per_tonne,
    ROUND((production_cost_per_tonne - standard_cost_per_tonne)
            * tonnes_produced, 2)                                       AS variance_gbp,
    raw_material_cost,
    energy_cost,
    labour_cost,
    overhead_cost
  FROM `@@PROJECT@@.@@CORE@@.production_cost`;

  -- 2. Management report — working capital + P&L, actual vs plan ──────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@FINANCE@@.management_report` AS
  SELECT
    financial_period,
    cost_centre,
    line_item,
    category,
    amount_gbp,
    plan_amount_gbp,
    ROUND(amount_gbp - plan_amount_gbp, 2)                              AS variance_gbp,
    SAFE_DIVIDE(amount_gbp - plan_amount_gbp, NULLIF(plan_amount_gbp, 0)) AS variance_pct
  FROM `@@PROJECT@@.@@STG@@.management`;

END;
