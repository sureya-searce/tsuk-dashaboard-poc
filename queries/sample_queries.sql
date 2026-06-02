-- ════════════════════════════════════════════════════════════════════════
-- TSUK Logistics Cost Analytics — Sample Queries
--
-- Two business questions per table, organised by layer (raw → stg → mart).
-- Fully-qualified for prj-tsuk-looker-sa-01; run directly in the BigQuery
-- console or via:  bq query --use_legacy_sql=false --location=EU '<query>'
--
-- Layers:
--   RAW  (searce_poc_raw)  — faithful JSON copy of each source feed
--   STG  (searce_poc_stg)  — one canonical movement grain + dimensions
--   MART (searce_poc_mart) — facts, rollups, anomalies, and the audit layer
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- RAW LAYER — "what exactly did we receive from each feed?"
-- ════════════════════════════════════════════════════════════════════════

-- ── raw_rail ──────────────────────────────────────────────────────────────

-- Q1. What commodities does DB Cargo move for us, and how is rail tonnage split?
SELECT
  INITCAP(LOWER(JSON_VALUE(payload_json, '$.tsuk_commodity'))) AS commodity,
  COUNT(*)                                                     AS movements,
  ROUND(SUM(SAFE_CAST(JSON_VALUE(payload_json, '$.tonnage_tops') AS NUMERIC)), 0) AS total_tonnes
FROM `prj-tsuk-looker-sa-01.searce_poc_raw.raw_rail`
GROUP BY commodity
ORDER BY total_tonnes DESC;

-- Q2. Which rail routes incur the most cancellation charges (paying for trains we didn't run)?
SELECT
  JSON_VALUE(payload_json, '$.route') AS route,
  COUNT(*)                            AS movements,
  ROUND(SUM(SAFE_CAST(JSON_VALUE(payload_json, '$.cancellation_revenue') AS NUMERIC)), 2) AS cancellation_gbp
FROM `prj-tsuk-looker-sa-01.searce_poc_raw.raw_rail`
WHERE SAFE_CAST(JSON_VALUE(payload_json, '$.cancellation_revenue') AS NUMERIC) <> 0
GROUP BY route
ORDER BY ABS(SUM(SAFE_CAST(JSON_VALUE(payload_json, '$.cancellation_revenue') AS NUMERIC))) DESC
LIMIT 15;


-- ── raw_road_uk ───────────────────────────────────────────────────────────

-- Q1. Who are our biggest UK road carriers by number of legs (supplier concentration)?
SELECT
  JSON_VALUE(payload_json, '$.carrier_name') AS carrier,
  COUNT(*)                                   AS legs,
  ROUND(SUM(SAFE_CAST(JSON_VALUE(payload_json, '$.purchase_cost') AS NUMERIC)), 0) AS spend_gbp
FROM `prj-tsuk-looker-sa-01.searce_poc_raw.raw_road_uk`
GROUP BY carrier
ORDER BY legs DESC
LIMIT 10;

-- Q2. What share of UK road legs are in vs out of reporting scope (Small Coil Test flag)?
SELECT
  JSON_VALUE(payload_json, '$.small_coil_test')          AS small_coil_test,
  COUNT(*)                                               AS legs,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)       AS pct_of_legs
FROM `prj-tsuk-looker-sa-01.searce_poc_raw.raw_road_uk`
GROUP BY small_coil_test
ORDER BY legs DESC;


-- ── raw_road_eu ───────────────────────────────────────────────────────────

-- Q1. What makes up our European road bill (charge-type breakdown)?
SELECT
  JSON_VALUE(payload_json, '$.charge_type') AS charge_type,
  COUNT(*)                                  AS charge_lines,
  ROUND(SUM(SAFE_CAST(JSON_VALUE(payload_json, '$.revenue_amount_gbp') AS NUMERIC)), 0) AS total_gbp
FROM `prj-tsuk-looker-sa-01.searce_poc_raw.raw_road_eu`
GROUP BY charge_type
ORDER BY total_gbp DESC
LIMIT 15;

-- Q2. Which cross-border trade lanes (country → country) are busiest?
SELECT
  JSON_VALUE(payload_json, '$.collection_country_code') AS from_country,
  JSON_VALUE(payload_json, '$.delivery_country_code')   AS to_country,
  COUNT(*)                                              AS charge_lines,
  ROUND(SUM(SAFE_CAST(JSON_VALUE(payload_json, '$.revenue_amount_gbp') AS NUMERIC)), 0) AS total_gbp
FROM `prj-tsuk-looker-sa-01.searce_poc_raw.raw_road_eu`
GROUP BY from_country, to_country
ORDER BY total_gbp DESC
LIMIT 15;


-- ════════════════════════════════════════════════════════════════════════
-- STG LAYER — canonical grain + the dimensions that drive the model
-- ════════════════════════════════════════════════════════════════════════

-- ── stg.dim_feed (feed registry) ──────────────────────────────────────────

-- Q1. What feeds, modes and managing providers are configured?
SELECT feed_id, mode, provider, provider_note
FROM `prj-tsuk-looker-sa-01.searce_poc_stg.dim_feed`
ORDER BY mode, feed_id;

-- Q2. How many feeds and providers do we cover per transport mode?
SELECT
  mode,
  COUNT(*)                  AS feeds,
  STRING_AGG(provider, ', ') AS providers
FROM `prj-tsuk-looker-sa-01.searce_poc_stg.dim_feed`
GROUP BY mode
ORDER BY mode;


-- ── stg.dim_capacity (the utilisation assumptions) ────────────────────────

-- Q1. What capacity assumptions are we using per feed and equipment type?
SELECT feed, equipment_key, capacity_tonnes, basis
FROM `prj-tsuk-looker-sa-01.searce_poc_stg.dim_capacity`
ORDER BY feed, capacity_tonnes DESC;

-- Q2. What is the assumed capacity range per feed (excluding the default fallback)?
SELECT
  feed,
  COUNT(*)             AS equipment_types,
  MIN(capacity_tonnes) AS min_capacity_t,
  MAX(capacity_tonnes) AS max_capacity_t
FROM `prj-tsuk-looker-sa-01.searce_poc_stg.dim_capacity`
WHERE equipment_key <> '__DEFAULT__'
GROUP BY feed
ORDER BY feed;


-- ── stg.shipments (cleaned, pre-mart) ─────────────────────────────────────

-- Q1. Before mart filtering, how complete is each feed (missing cost / tonnage)?
SELECT
  feed,
  COUNT(*)                                        AS shipments,
  COUNTIF(NOT (tonnes > 0))                        AS missing_tonnage,
  COUNTIF(cost_gbp IS NULL OR cost_gbp <= 0)       AS missing_or_zero_cost
FROM `prj-tsuk-looker-sa-01.searce_poc_stg.shipments`
GROUP BY feed
ORDER BY feed;

-- Q2. What does the cost-per-tonne distribution look like per mode (median vs P90)?
SELECT
  mode,
  ROUND(APPROX_QUANTILES(cost_per_tonne, 100)[OFFSET(50)], 2) AS median_cost_per_tonne,
  ROUND(APPROX_QUANTILES(cost_per_tonne, 100)[OFFSET(90)], 2) AS p90_cost_per_tonne,
  ROUND(MAX(cost_per_tonne), 2)                               AS max_cost_per_tonne
FROM `prj-tsuk-looker-sa-01.searce_poc_stg.shipments`
WHERE cost_per_tonne IS NOT NULL
GROUP BY mode
ORDER BY mode;


-- ════════════════════════════════════════════════════════════════════════
-- MART LAYER — the questions Finance and Supply Chain actually ask
-- ════════════════════════════════════════════════════════════════════════

-- ── mart.movements (the single source of truth fact table) ────────────────

-- Q1. FINANCE: what is our cost per load and per tonne, by mode and trip type?
SELECT
  mode,
  trip_type,
  COUNT(*)                                            AS loads,
  ROUND(SUM(cost_gbp), 0)                             AS total_cost_gbp,
  ROUND(SAFE_DIVIDE(SUM(cost_gbp), SUM(tonnes)), 2)   AS cost_per_tonne,
  ROUND(AVG(cost_gbp), 2)                             AS avg_cost_per_load
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.movements`
WHERE include_flag
GROUP BY mode, trip_type
ORDER BY total_cost_gbp DESC;

-- Q2. SUPPLY CHAIN: how many loads run under-utilised (paying to move air), by feed?
--     Utilisation is assumption-based (see dim_capacity); out-of-range values excluded.
SELECT
  feed,
  COUNTIF(utilisation_pct < 40)                              AS loads_under_40pct,
  COUNTIF(utilisation_pct >= 40 AND utilisation_pct < 60)    AS loads_40_to_60pct,
  COUNTIF(utilisation_pct >= 60 AND utilisation_pct <= 100)  AS loads_60_to_100pct,
  ROUND(AVG(IF(utilisation_in_range, utilisation_pct, NULL)), 1) AS avg_utilisation_pct
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.movements`
WHERE include_flag
GROUP BY feed
ORDER BY feed;


-- ── mart.lane_monthly (lane × month rollup) ───────────────────────────────

-- Q1. Which lanes cost the most per tonne (with meaningful volume)?
SELECT
  lane,
  mode,
  SUM(loads)                                                  AS loads,
  ROUND(SUM(total_tonnes), 0)                                 AS total_tonnes,
  ROUND(SAFE_DIVIDE(SUM(total_cost_gbp), SUM(total_tonnes)), 2) AS cost_per_tonne
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.lane_monthly`
GROUP BY lane, mode
HAVING SUM(total_tonnes) > 500
ORDER BY cost_per_tonne DESC
LIMIT 10;

-- Q2. Where does our lane spend concentrate, and how does cross-border compare to domestic?
SELECT
  trip_type,
  lane,
  SUM(loads)                  AS loads,
  ROUND(SUM(total_cost_gbp), 0) AS spend_gbp
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.lane_monthly`
GROUP BY trip_type, lane
ORDER BY spend_gbp DESC
LIMIT 15;


-- ── mart.carrier_monthly (carrier × month rollup) ─────────────────────────

-- Q1. Carrier concentration: top carriers by spend and their cost per tonne.
SELECT
  carrier,
  provider,
  SUM(loads)                                                  AS loads,
  ROUND(SUM(total_cost_gbp), 0)                               AS spend_gbp,
  ROUND(SAFE_DIVIDE(SUM(total_cost_gbp), SUM(total_tonnes)), 2) AS cost_per_tonne
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.carrier_monthly`
GROUP BY carrier, provider
ORDER BY spend_gbp DESC
LIMIT 10;

-- Q2. Which carriers run the emptiest trucks (worst utilisation, min 50 loads)?
SELECT
  carrier,
  SUM(loads)                            AS loads,
  ROUND(AVG(avg_utilisation_pct), 1)    AS avg_utilisation_pct
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.carrier_monthly`
GROUP BY carrier
HAVING SUM(loads) >= 50
ORDER BY avg_utilisation_pct ASC
LIMIT 10;


-- ── mart.kpi_monthly (headline KPI trend) ─────────────────────────────────

-- Q1. Month-on-month total logistics cost and cost-per-tonne, by mode.
SELECT
  financial_period,
  mode,
  ROUND(SUM(total_cost_gbp), 0)                               AS total_cost_gbp,
  ROUND(SAFE_DIVIDE(SUM(total_cost_gbp), SUM(total_tonnes)), 2) AS cost_per_tonne
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.kpi_monthly`
GROUP BY financial_period, mode
ORDER BY financial_period, mode;

-- Q2. How many under-utilised loads do we run each month, by feed?
SELECT
  financial_period,
  feed,
  SUM(loads)                   AS loads,
  SUM(loads_under_60pct_util)  AS loads_under_60pct
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.kpi_monthly`
GROUP BY financial_period, feed
ORDER BY financial_period, feed;


-- ── mart.anomalies (rule-based cost-leakage digest) ───────────────────────

-- Q1. The Top-10 cost-leakage anomalies by £ impact (the demo's "wow" tile).
SELECT
  rule_id,
  feed,
  carrier,
  lane,
  ROUND(cost_gbp, 2)        AS cost_gbp,
  ROUND(utilisation_pct, 1) AS utilisation_pct,
  ROUND(impact_score, 0)    AS impact_score
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.anomalies`
ORDER BY impact_score DESC
LIMIT 10;

-- Q2. What is our total exposure by anomaly type (where is the money leaking)?
SELECT
  rule_id,
  rule_label,
  COUNT(*)                          AS anomalies,
  ROUND(SUM(ABS(cost_gbp)), 0)      AS exposure_gbp
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.anomalies`
GROUP BY rule_id, rule_label
ORDER BY exposure_gbp DESC;


-- ── mart.reconciliation (the evidence / audit layer) ──────────────────────

-- Q1. AUDIT: do our computed totals tie back to the source files, per feed?
SELECT
  feed,
  raw_rows,
  movements,
  ROUND(source_cost_gbp, 0)        AS source_cost_gbp,
  ROUND(computed_cost_gbp, 0)      AS computed_cost_gbp,
  ROUND(cost_delta, 2)             AS cost_delta,
  ROUND(cost_delta_pct * 100, 3)   AS cost_delta_pct
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.reconciliation`
ORDER BY feed;

-- Q2. What is our reconciled total logistics spend and movement count across all feeds?
SELECT
  ROUND(SUM(computed_cost_gbp), 0) AS total_cost_gbp,
  SUM(movements)                   AS total_movements
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.reconciliation`;


-- ── mart.dq_flags (data-quality register) ─────────────────────────────────

-- Q1. What data-quality issues exist, and how many rows fall under each reason?
SELECT
  flag_reason,
  COUNT(*) AS flagged_rows
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.dq_flags`
GROUP BY flag_reason
ORDER BY flagged_rows DESC;

-- Q2. Which feeds carry the most data-quality issues, broken down by reason?
SELECT
  feed,
  flag_reason,
  COUNT(*) AS flagged_rows
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.dq_flags`
GROUP BY feed, flag_reason
ORDER BY feed, flagged_rows DESC;


-- ── mart.assumptions (non-source inputs, labelled) ────────────────────────

-- Q1. What non-source assumptions underpin the numbers (capacity + provider inferences)?
SELECT assumption_type, feed, equipment_key, capacity_tonnes, basis, note
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.assumptions`
ORDER BY assumption_type, feed, equipment_key;

-- Q2. Which capacity assumptions influence the most loads (where accuracy matters most)?
SELECT
  a.feed,
  a.equipment_key,
  a.capacity_tonnes,
  COUNT(m.movement_id) AS loads_using_assumption
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.assumptions` a
LEFT JOIN `prj-tsuk-looker-sa-01.searce_poc_mart.movements` m
  ON m.feed = a.feed AND m.equipment_type = a.equipment_key
WHERE a.assumption_type = 'capacity'
GROUP BY a.feed, a.equipment_key, a.capacity_tonnes
ORDER BY loads_using_assumption DESC
LIMIT 15;
