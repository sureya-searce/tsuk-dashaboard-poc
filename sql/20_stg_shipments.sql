-- ─────────────────────────────────────────────────────────────────────────
-- STG — normalise the per-feed raw tables into ONE canonical movement grain,
-- with provider / mode / carrier / trip_type as first-class dimensions.
--
--   rail     : 1 source row  = 1 movement              → pass through
--   road_uk  : 1 source row  = 1 leg (cost event)      → pass through (leg grain)
--   road_eu  : N source rows = 1 shipment (charge lines)→ AGGREGATE to shipment
--
-- Cost-to-TSUK per feed (see docs/kpi-logic.md):
--   rail     : total_excl_cancellation (clean freight); cancellation tracked apart
--   road_uk  : purchase_cost (procurement), NOT sales_cost (onward charge)
--   road_eu  : SUM(revenue_amount_gbp) across charge lines (net of rebates)
--
-- mode + provider come from stg.dim_feed (single editable source).
-- carrier  = the per-trip sub-carrier (the company actually doing the trip).
-- trip_type= Domestic | Cross-border (from origin↔dest country).
--
-- Called by the Workflow as: CALL `@@PROJECT@@.@@STG@@.sp_normalise`()
-- ─────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE `@@PROJECT@@.@@STG@@.sp_normalise`()
BEGIN

  DECLARE rail_wagon_cap NUMERIC DEFAULT (
    SELECT capacity_tonnes FROM `@@PROJECT@@.@@STG@@.dim_capacity`
    WHERE feed = 'rail' AND equipment_key = 'WAGON'
  );

  CREATE OR REPLACE TABLE `@@PROJECT@@.@@STG@@.shipments`
  PARTITION BY movement_date
  CLUSTER BY feed, lane AS

  WITH
  -- ───────────────────────────── RAIL ─────────────────────────────
  rail_src AS (
    SELECT row_idx, source_file, PARSE_JSON(payload_json) AS j
    FROM `@@PROJECT@@.@@RAW@@.raw_rail`
  ),
  rail AS (
    SELECT
      'rail' AS feed,
      CAST(FARM_FINGERPRINT(CONCAT(source_file, '|', CAST(row_idx AS STRING))) AS STRING) AS movement_id,
      source_file,
      DATE(SAFE_CAST(JSON_VALUE(j, '$.date_delivered') AS TIMESTAMP)) AS movement_date,
      INITCAP(TRIM(JSON_VALUE(j, '$.origin')))      AS origin,
      INITCAP(TRIM(JSON_VALUE(j, '$.destination')))  AS destination,
      'GB' AS origin_country,
      'GB' AS dest_country,
      INITCAP(LOWER(TRIM(JSON_VALUE(j, '$.tsuk_commodity')))) AS commodity,
      'WAGON' AS equipment_type,
      'DB Cargo' AS carrier,                 -- rail feed has a single carrier
      CAST(NULL AS STRING) AS customer,
      CAST(NULL AS STRING) AS region,
      SAFE_CAST(JSON_VALUE(j, '$.tonnage_tops') AS NUMERIC) AS tonnes,
      SAFE_CAST(JSON_VALUE(j, '$.total_excl_cancellation') AS NUMERIC) AS cost_gbp,
      -- Finance basis = base contracted freight (haulage), excluding fuel/handling.
      SAFE_CAST(JSON_VALUE(j, '$.haulage_revenue') AS NUMERIC)         AS finance_cost_gbp,
      SAFE_CAST(JSON_VALUE(j, '$.haulage_revenue') AS NUMERIC)         AS freight_gbp,
      SAFE_CAST(JSON_VALUE(j, '$.fuel_surcharge') AS NUMERIC)          AS fuel_gbp,
      SAFE_CAST(JSON_VALUE(j, '$.cancellation_revenue') AS NUMERIC)    AS cancellation_gbp,
      CAST(NULL AS NUMERIC) AS distance_miles,
      TRUE AS include_flag,
      SAFE_CAST(JSON_VALUE(j, '$.wagons_received') AS NUMERIC) * rail_wagon_cap AS capacity_tonnes
    FROM rail_src
  ),

  -- ──────────────────────────── ROAD UK ───────────────────────────
  uk_src AS (
    SELECT row_idx, source_file, PARSE_JSON(payload_json) AS j
    FROM `@@PROJECT@@.@@RAW@@.raw_road_uk`
  ),
  uk AS (
    SELECT
      'road_uk' AS feed,
      CAST(FARM_FINGERPRINT(CONCAT(source_file, '|', CAST(row_idx AS STRING))) AS STRING) AS movement_id,
      source_file,
      DATE(SAFE_CAST(JSON_VALUE(j, '$.delivery_date_start') AS TIMESTAMP)) AS movement_date,
      INITCAP(TRIM(JSON_VALUE(j, '$.loading_city')))  AS origin,
      INITCAP(TRIM(JSON_VALUE(j, '$.delivery_city')))  AS destination,
      'GB' AS origin_country,
      'GB' AS dest_country,
      INITCAP(LOWER(TRIM(JSON_VALUE(j, '$.commodity')))) AS commodity,
      UPPER(TRIM(JSON_VALUE(j, '$.equipment_type'))) AS equipment_type,
      INITCAP(TRIM(JSON_VALUE(j, '$.carrier_name'))) AS carrier,   -- 54+ carriers
      INITCAP(TRIM(JSON_VALUE(j, '$.ordering_party'))) AS customer,
      TRIM(JSON_VALUE(j, '$.region')) AS region,
      SAFE_CAST(JSON_VALUE(j, '$.order_weight_t') AS NUMERIC) AS tonnes,
      SAFE_CAST(JSON_VALUE(j, '$.purchase_cost') AS NUMERIC)  AS cost_gbp,
      -- Finance basis = procurement cost net of fuel surcharge + handling/accessorials.
      (SAFE_CAST(JSON_VALUE(j, '$.purchase_cost') AS NUMERIC)
         - IFNULL(SAFE_CAST(JSON_VALUE(j, '$.fuel_surcharge') AS NUMERIC), 0)
         - IFNULL(SAFE_CAST(JSON_VALUE(j, '$.handling_charge') AS NUMERIC), 0)) AS finance_cost_gbp,
      SAFE_CAST(JSON_VALUE(j, '$.purchase_cost') AS NUMERIC)  AS freight_gbp,
      CAST(NULL AS NUMERIC) AS fuel_gbp,
      CAST(NULL AS NUMERIC) AS cancellation_gbp,
      SAFE_CAST(JSON_VALUE(j, '$.order_distance') AS NUMERIC) AS distance_miles,
      (UPPER(TRIM(JSON_VALUE(j, '$.small_coil_test'))) = 'INCLUDE') AS include_flag,
      CAST(NULL AS NUMERIC) AS capacity_tonnes
    FROM uk_src
  ),

  -- ──────────────────────────── ROAD EU ───────────────────────────
  eu_src AS (
    SELECT source_file, PARSE_JSON(payload_json) AS j
    FROM `@@PROJECT@@.@@RAW@@.raw_road_eu`
  ),
  eu_lines AS (
    SELECT
      source_file,
      JSON_VALUE(j, '$.code')                  AS code,
      JSON_VALUE(j, '$.customer_name')         AS customer_name,
      JSON_VALUE(j, '$.charter_haulier_name')  AS carrier,        -- 62+ hauliers
      JSON_VALUE(j, '$.actual_col_date_time')  AS col_dt,
      JSON_VALUE(j, '$.actual_del_date_time')  AS del_dt,
      JSON_VALUE(j, '$.month')                 AS month_val,
      INITCAP(LOWER(TRIM(JSON_VALUE(j, '$.commodity')))) AS commodity,
      INITCAP(TRIM(JSON_VALUE(j, '$.collection_town'))) AS collection_town,
      INITCAP(TRIM(JSON_VALUE(j, '$.delivery_town')))   AS delivery_town,
      JSON_VALUE(j, '$.collection_country_code') AS origin_country,
      JSON_VALUE(j, '$.delivery_country_code')   AS dest_country,
      UPPER(TRIM(JSON_VALUE(j, '$.equipment_type'))) AS equipment_type,
      JSON_VALUE(j, '$.charge_type')             AS charge_type,
      SAFE_CAST(JSON_VALUE(j, '$.revenue_amount_gbp') AS NUMERIC) AS amount_gbp,
      SAFE_CAST(JSON_VALUE(j, '$.gross_weight') AS NUMERIC)       AS gross_weight,
      SAFE_CAST(JSON_VALUE(j, '$.miles') AS NUMERIC)              AS miles
    FROM eu_src
  ),
  eu AS (
    SELECT
      'road_eu' AS feed,
      CAST(FARM_FINGERPRINT(CONCAT(
        source_file, '|', IFNULL(code,''), '|', IFNULL(col_dt,''), '|',
        IFNULL(del_dt,''), '|', IFNULL(delivery_town,''), '|',
        CAST(IFNULL(gross_weight, 0) AS STRING)
      )) AS STRING) AS movement_id,
      ANY_VALUE(source_file) AS source_file,
      -- Delivery date preferred; fall back to collection date, then the feed's
      -- month field, so no shipment is dropped for an unparseable delivery date.
      DATE(COALESCE(
        SAFE_CAST(MAX(del_dt) AS TIMESTAMP),
        SAFE_CAST(MAX(col_dt) AS TIMESTAMP),
        SAFE_CAST(MAX(month_val) AS TIMESTAMP)
      )) AS movement_date,
      ANY_VALUE(collection_town) AS origin,
      ANY_VALUE(delivery_town)   AS destination,
      ANY_VALUE(origin_country)  AS origin_country,
      ANY_VALUE(dest_country)    AS dest_country,
      ANY_VALUE(commodity) AS commodity,
      ANY_VALUE(equipment_type) AS equipment_type,
      INITCAP(ANY_VALUE(carrier)) AS carrier,
      INITCAP(ANY_VALUE(customer_name)) AS customer,
      CAST(NULL AS STRING) AS region,
      MAX(gross_weight) AS tonnes,
      SUM(amount_gbp) AS cost_gbp,
      -- Finance basis = base Freight charge lines only (excludes Fuel/Maut/Mgmt Fee).
      SUM(IF(charge_type = 'Freight', amount_gbp, 0)) AS finance_cost_gbp,
      SUM(IF(charge_type = 'Freight', amount_gbp, 0)) AS freight_gbp,
      SUM(IF(charge_type LIKE '%Fuel Surcharge%', amount_gbp, 0)) AS fuel_gbp,
      CAST(NULL AS NUMERIC) AS cancellation_gbp,
      MAX(miles) AS distance_miles,
      TRUE AS include_flag,
      CAST(NULL AS NUMERIC) AS capacity_tonnes
    FROM eu_lines
    GROUP BY movement_id
  ),

  -- ──────────────────────── UNION + CAPACITY ──────────────────────
  unioned AS (
    SELECT * FROM rail
    UNION ALL SELECT * FROM uk
    UNION ALL SELECT * FROM eu
  ),
  with_capacity AS (
    SELECT
      u.* REPLACE (
        CASE
          WHEN u.feed = 'rail' THEN u.capacity_tonnes
          ELSE COALESCE(dc.capacity_tonnes, dd.capacity_tonnes)
        END AS capacity_tonnes
      )
    FROM unioned u
    LEFT JOIN `@@PROJECT@@.@@STG@@.dim_capacity` dc
      ON dc.feed = u.feed AND dc.equipment_key = u.equipment_type
    LEFT JOIN `@@PROJECT@@.@@STG@@.dim_capacity` dd
      ON dd.feed = u.feed AND dd.equipment_key = '__DEFAULT__'
  )

  SELECT
    wc.feed,
    df.mode,
    df.provider,
    wc.movement_id,
    wc.source_file,
    wc.movement_date,
    FORMAT_DATE('%Y-%m', wc.movement_date) AS financial_period,
    wc.origin,
    wc.destination,
    CONCAT(IFNULL(wc.origin, '?'), ' → ', IFNULL(wc.destination, '?')) AS lane,
    wc.origin_country,
    wc.dest_country,
    (wc.origin_country != wc.dest_country) AS is_international,
    IF(wc.origin_country != wc.dest_country, 'Cross-border', 'Domestic') AS trip_type,
    wc.commodity,
    wc.equipment_type,
    wc.carrier,
    wc.customer,
    wc.region,
    wc.tonnes,
    wc.cost_gbp,
    wc.finance_cost_gbp,
    wc.freight_gbp,
    wc.fuel_gbp,
    wc.cancellation_gbp,
    wc.distance_miles,
    SAFE_DIVIDE(wc.cost_gbp, NULLIF(wc.tonnes, 0)) AS cost_per_tonne,
    SAFE_DIVIDE(wc.finance_cost_gbp, NULLIF(wc.tonnes, 0)) AS finance_cost_per_tonne,
    wc.capacity_tonnes,
    ROUND(SAFE_DIVIDE(wc.tonnes, NULLIF(wc.capacity_tonnes, 0)) * 100, 1) AS utilisation_pct,
    wc.include_flag
  FROM with_capacity wc
  LEFT JOIN `@@PROJECT@@.@@STG@@.dim_feed` df ON df.feed_id = wc.feed
  WHERE wc.movement_date IS NOT NULL;

END;
