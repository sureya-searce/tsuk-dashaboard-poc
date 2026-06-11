-- ─────────────────────────────────────────────────────────────────────────
-- Sample business queries — domain-owned medallion on infraappsandbox.
-- Replace `infraappsandbox` if you deployed to a different project.
--
-- Layout:  raw → stg (silver, shared) → core (gold, shared governed)
--          + finance / supplychain (gold, team-owned)
-- ─────────────────────────────────────────────────────────────────────────

-- ══ 0. The receipts — every feed ties to source, delta £0 ══════════════════
SELECT feed, raw_rows, movements,
       ROUND(source_cost_gbp, 0)   AS source,
       ROUND(computed_cost_gbp, 0) AS computed,
       ROUND(cost_delta, 2)        AS delta
FROM `infraappsandbox.searce_poc_core.reconciliation`
ORDER BY feed;

-- ══ 1. THE governed cross-team KPI — "cost per tonne" means three things ════
--    Same source of truth, three legitimate readings. By commodity.
SELECT
  commodity,
  ROUND(SAFE_DIVIDE(SUM(production_cost_gbp), SUM(tonnes_produced)), 2) AS finance_cost_per_tonne,
  ROUND(SAFE_DIVIDE(SUM(transport_cost_gbp), SUM(tonnes_moved)), 2)     AS logistics_cost_per_tonne,
  ROUND(SAFE_DIVIDE(SUM(production_cost_gbp), SUM(tonnes_produced))
      + SAFE_DIVIDE(SUM(transport_cost_gbp), SUM(tonnes_moved)), 2)     AS landed_cost_per_tonne
FROM `infraappsandbox.searce_poc_core.cost_per_tonne`
GROUP BY commodity
ORDER BY commodity;

-- ══ 2. Within transport: Finance basis vs Logistics basis (the finer split) ═
SELECT
  feed, mode,
  ROUND(SUM(cost_gbp), 0)                                   AS all_in_cost,
  ROUND(SUM(finance_cost_gbp), 0)                           AS base_freight_cost,
  ROUND(SAFE_DIVIDE(SUM(cost_gbp), SUM(tonnes)), 2)         AS logistics_cpt,
  ROUND(SAFE_DIVIDE(SUM(finance_cost_gbp), SUM(tonnes)), 2) AS finance_cpt
FROM `infraappsandbox.searce_poc_core.movements`
WHERE include_flag
GROUP BY feed, mode
ORDER BY feed;

-- ══ 3. Finance — production cost variance to standard (£ impact) ════════════
SELECT financial_period, site, commodity,
       ROUND(production_cost_per_tonne, 2) AS actual_cpt,
       ROUND(standard_cost_per_tonne, 2)   AS standard_cpt,
       ROUND(variance_gbp, 0)              AS variance_gbp
FROM `infraappsandbox.searce_poc_finance.cost_analysis`
ORDER BY ABS(variance_gbp) DESC
LIMIT 10;

-- ══ 4. Finance — working capital this period vs plan ════════════════════════
SELECT financial_period, cost_centre, line_item,
       ROUND(amount_gbp, 0)      AS actual,
       ROUND(plan_amount_gbp, 0) AS plan,
       ROUND(variance_gbp, 0)    AS variance
FROM `infraappsandbox.searce_poc_finance.management_report`
WHERE category = 'Working Capital'
ORDER BY financial_period, cost_centre, line_item;

-- ══ 5. Supply Chain — carrier concentration (negotiation lever) ═════════════
SELECT carrier,
       ROUND(SUM(total_cost_gbp), 0) AS spend_gbp,
       SUM(loads)                    AS loads
FROM `infraappsandbox.searce_poc_supplychain.carrier_spend`
WHERE feed = 'road_uk'
GROUP BY carrier
ORDER BY spend_gbp DESC
LIMIT 5;

-- ══ 6. Supply Chain — Top-10 cost-leakage anomalies by £ impact ═════════════
SELECT rule_label, feed, lane, carrier,
       ROUND(cost_gbp, 0) AS cost, ROUND(utilisation_pct, 1) AS util_pct,
       ROUND(impact_score, 0) AS impact
FROM `infraappsandbox.searce_poc_supplychain.anomalies`
ORDER BY impact_score DESC
LIMIT 10;

-- ══ 7. Governance — who owns what (shared vs team-owned) ════════════════════
SELECT layer, owner, object, grain
FROM `infraappsandbox.searce_poc_core.data_catalog`
ORDER BY layer, owner, object;
