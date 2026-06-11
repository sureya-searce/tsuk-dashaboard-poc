-- ─────────────────────────────────────────────────────────────────────────
-- GOLD core (shared, governed) — the single source of truth every team reads.
--
-- Holds ONLY conformed facts and the cross-team KPIs that must be defined once:
--   core.movements      : conformed logistics fact (one row per movement)
--   core.production_cost : conformed finance production fact (site×commodity×period)
--   core.cost_per_tonne  : THE governed cross-team KPI — finance | transport | landed
--                          cost per tonne, by commodity × period. Defined here once;
--                          every team mart and Looker model inherits it.
--   core.data_catalog    : ownership registry (which tables are shared vs team-owned)
--
-- Team-specific rollups (utilisation, lane, carrier, anomalies; finance cost
-- analysis, management report) live in the OWNING team's gold dataset, not here.
--
-- Called by the Workflow as: CALL `@@PROJECT@@.@@CORE@@.sp_build_core`()
-- ─────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE `@@PROJECT@@.@@CORE@@.sp_build_core`()
OPTIONS (strict_mode = false)  -- reads stg.* tables created at runtime
BEGIN

  -- 1. Conformed logistics fact ───────────────────────────────────────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@CORE@@.movements`
  PARTITION BY movement_date
  CLUSTER BY feed, lane AS
  SELECT
    *,
    -- NULL-safe: in BigQuery `NULL > 0` is NULL (not FALSE), which would drop
    -- missing-tonnage rows from NOT has_tonnes filters (R2 anomaly, dq_flags).
    (tonnes IS NOT NULL AND tonnes > 0)                   AS has_tonnes,
    (cost_gbp IS NOT NULL AND cost_gbp > 0)               AS has_cost,
    (capacity_tonnes IS NOT NULL AND capacity_tonnes > 0) AS has_capacity,
    (utilisation_pct IS NOT NULL
       AND utilisation_pct BETWEEN 0 AND 100)             AS utilisation_in_range
  FROM `@@PROJECT@@.@@STG@@.shipments`;

  -- 2. Conformed finance production fact ───────────────────────────────────
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@CORE@@.production_cost` AS
  SELECT
    p.financial_period,
    p.site,
    p.commodity,
    p.tonnes_produced,
    p.works_cost_gbp,
    p.raw_material_cost,
    p.energy_cost,
    p.labour_cost,
    p.overhead_cost,
    p.standard_cost_per_tonne,
    SAFE_DIVIDE(p.works_cost_gbp, NULLIF(p.tonnes_produced, 0)) AS production_cost_per_tonne
  FROM `@@PROJECT@@.@@STG@@.production` p;

  -- 3. THE governed cross-team KPI — cost per tonne, three legitimate bases ─
  --    Same words, traceable numbers, one source. Finance reads production;
  --    Logistics reads transport; the org-agreed metric is landed = both.
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@CORE@@.cost_per_tonne` AS
  WITH prod AS (
    SELECT financial_period, commodity,
           SUM(works_cost_gbp)   AS production_cost_gbp,
           SUM(tonnes_produced)  AS tonnes_produced,
           SAFE_DIVIDE(SUM(works_cost_gbp), NULLIF(SUM(tonnes_produced), 0)) AS production_cost_per_tonne
    FROM `@@PROJECT@@.@@CORE@@.production_cost`
    GROUP BY financial_period, commodity
  ),
  trans AS (
    SELECT financial_period, commodity,
           SUM(cost_gbp)         AS transport_cost_gbp,
           SUM(finance_cost_gbp) AS transport_finance_cost_gbp,
           SUM(tonnes)           AS tonnes_moved,
           SAFE_DIVIDE(SUM(cost_gbp), NULLIF(SUM(tonnes), 0)) AS transport_cost_per_tonne
    FROM `@@PROJECT@@.@@CORE@@.movements`
    WHERE include_flag AND commodity IS NOT NULL
    GROUP BY financial_period, commodity
  )
  SELECT
    COALESCE(p.financial_period, t.financial_period) AS financial_period,
    COALESCE(p.commodity, t.commodity)               AS commodity,
    p.production_cost_per_tonne,
    t.transport_cost_per_tonne,
    IFNULL(p.production_cost_per_tonne, 0) + IFNULL(t.transport_cost_per_tonne, 0) AS landed_cost_per_tonne,
    p.production_cost_gbp,
    t.transport_cost_gbp,
    p.tonnes_produced,
    t.tonnes_moved
  FROM prod p
  FULL OUTER JOIN trans t
    ON p.financial_period = t.financial_period AND p.commodity = t.commodity;

  -- 4. Ownership registry — makes shared-vs-team-owned explicit & inspectable
  CREATE OR REPLACE TABLE `@@PROJECT@@.@@CORE@@.data_catalog` AS
  SELECT * FROM UNNEST([
    STRUCT('raw'    AS layer, 'shared' AS owner, 'raw_*' AS object, 'per-feed JSON landing, full lineage' AS grain),
    ('stg',         'shared',      'shipments',            'one clean logistics movement'),
    ('stg',         'shared',      'production',           'site x commodity x period works cost'),
    ('stg',         'shared',      'management',           'period x cost centre x line item'),
    ('stg',         'shared',      'dim_commodity/site/calendar/feed/capacity', 'conformed dimensions'),
    ('core',        'shared',      'movements',            'conformed logistics fact'),
    ('core',        'shared',      'production_cost',      'conformed finance production fact'),
    ('core',        'shared',      'cost_per_tonne',       'GOVERNED cross-team KPI: finance|transport|landed'),
    ('core',        'shared',      'reconciliation',       'source-vs-computed receipts'),
    ('finance',     'finance',     'cost_analysis',        'Finance lens: production cost/t + variance'),
    ('finance',     'finance',     'management_report',    'working capital + P&L, actual vs plan'),
    ('supplychain', 'supplychain', 'utilisation',          'load utilisation vs assumed capacity'),
    ('supplychain', 'supplychain', 'lane_performance',     'lane x month cost/tonne/utilisation'),
    ('supplychain', 'supplychain', 'carrier_spend',        'carrier x month spend & concentration'),
    ('supplychain', 'supplychain', 'anomalies',            'rule-based cost-leakage Top-N')
  ]);

END;
