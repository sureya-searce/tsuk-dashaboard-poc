-- ─────────────────────────────────────────────────────────────────────────
-- CONFORMED DIMENSIONS (silver, shared) — the keys every team joins on.
--
-- These are the "one trusted foundation" join keys. Finance and Supply Chain
-- both reference dim_commodity / dim_site / dim_calendar, so a cross-team KPI
-- like cost-per-tonne lines up by commodity × period across domains. Conformed
-- dimensions are centrally governed (shared), never team-owned.
-- ─────────────────────────────────────────────────────────────────────────

-- ── Commodity (the cross-domain join key: finance production ↔ logistics) ──
CREATE TABLE IF NOT EXISTS `@@PROJECT@@.@@STG@@.dim_commodity` (
  commodity        STRING,
  commodity_group  STRING,
  description       STRING
);
TRUNCATE TABLE `@@PROJECT@@.@@STG@@.dim_commodity`;
INSERT INTO `@@PROJECT@@.@@STG@@.dim_commodity` (commodity, commodity_group, description) VALUES
  ('Coil',  'Flat',          'Hot/cold rolled coil'),
  ('Slab',  'Semi-finished', 'Cast slab'),
  ('Plate', 'Flat',          'Heavy plate'),
  ('Ore',   'Raw material',  'Iron ore / feedstock');

-- ── Site / plant (shared production + logistics origin geography) ──────────
CREATE TABLE IF NOT EXISTS `@@PROJECT@@.@@STG@@.dim_site` (
  site    STRING,
  region  STRING,
  nation  STRING
);
TRUNCATE TABLE `@@PROJECT@@.@@STG@@.dim_site`;
INSERT INTO `@@PROJECT@@.@@STG@@.dim_site` (site, region, nation) VALUES
  ('Port Talbot', 'South Wales', 'Wales'),
  ('Llanwern',    'South Wales', 'Wales'),
  ('Trostre',     'South Wales', 'Wales'),
  ('Shotton',     'North Wales', 'Wales');

-- ── Calendar (shared time conformance for FY26 = Apr-2025 → Mar-2026) ──────
CREATE OR REPLACE TABLE `@@PROJECT@@.@@STG@@.dim_calendar` AS
SELECT
  FORMAT_DATE('%Y-%m', d)                         AS period,
  'FY26'                                          AS fiscal_year,
  -- FY starts April: Apr-Jun=Q1 … Jan-Mar=Q4.
  CONCAT('Q', CAST(DIV(MOD(EXTRACT(MONTH FROM d) - 4 + 12, 12), 3) + 1 AS STRING)) AS fiscal_quarter,
  FORMAT_DATE('%B', d)                            AS month_name,
  d                                               AS period_start
FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2025-04-01', DATE '2026-03-01', INTERVAL 1 MONTH)) AS d;
