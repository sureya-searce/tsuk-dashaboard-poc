-- ─────────────────────────────────────────────────────────────────────────
-- dim_capacity — the "utilisation" KPI input.
--
-- None of the three feeds contains a vehicle/wagon MAX capacity, so utilisation
-- (tonnes carried ÷ capacity paid for) cannot be computed from source data
-- alone. This is the "improvise from the data" piece: we seed sensible,
-- DOCUMENTED capacity assumptions per (source, equipment_type) that TSUK can
-- refine with their real fleet spec. Values are conservative max-payload
-- estimates for steel-carrying equipment.
--
-- For rail, capacity is per-WAGON; the stg layer multiplies by wagons received.
-- ─────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `@@PROJECT@@.@@STG@@.dim_capacity` (
  feed              STRING,    -- rail | road_uk | road_eu
  equipment_key     STRING,    -- UPPER(TRIM(equipment_type)); 'WAGON' for rail
  capacity_tonnes   NUMERIC,   -- max payload per vehicle (per wagon for rail)
  basis             STRING     -- note on the assumption
);

-- Idempotent reseed.
TRUNCATE TABLE `@@PROJECT@@.@@STG@@.dim_capacity`;

INSERT INTO `@@PROJECT@@.@@STG@@.dim_capacity` (feed, equipment_key, capacity_tonnes, basis) VALUES
  -- Rail: per-wagon payload for bogie steel carriers (BAA/BBA class).
  ('rail',     'WAGON',                            75.0,  'Assumed bogie steel wagon max payload, per wagon'),

  -- Road UK: 44t GVW artic ≈ 29t payload; rigids lower.
  ('road_uk',  'COIL CARRIER',                     29.0,  'Artic coil carrier max payload'),
  ('road_uk',  'FLAT',                             29.0,  'Artic flatbed max payload'),
  ('road_uk',  'FLAT/SLIDER - PINS & GOAL POST',   29.0,  'Artic flat/slider max payload'),
  ('road_uk',  'H20 1.5 PINS',                     24.0,  'Assumed mid-size rigid/artic'),
  ('road_uk',  '28FT TRAILER PINS/GP',             20.0,  '28ft trailer, reduced payload'),
  ('road_uk',  'P&P RIGID',                        18.0,  'Rigid vehicle, reduced payload'),
  ('road_uk',  '__DEFAULT__',                      29.0,  'Default UK artic payload'),

  -- Road EU: cross-border artics.
  ('road_eu',  'COIL CARRIER',                     27.0,  'EU coil carrier max payload'),
  ('road_eu',  'EUROLINER',                        24.0,  'Curtainsider max payload'),
  ('road_eu',  'EXTENDER',                         24.0,  'Extendable trailer max payload'),
  ('road_eu',  'FLAT BED',                         24.0,  'EU flatbed max payload'),
  ('road_eu',  '__DEFAULT__',                      25.0,  'Default EU artic payload');
