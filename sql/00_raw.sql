-- ─────────────────────────────────────────────────────────────────────────
-- RAW layer — ONE table per FEED (file shape), not per carrier.
--
-- A "feed" is the monthly file's shape / managing partner (rail = DB Cargo,
-- road_uk = UK managed road network, road_eu = EU charter network). Carriers
-- (50–60+ per road feed) live INSIDE the rows as a column, not as separate
-- tables — so onboarding a new carrier never changes the schema.
--
-- Each feed table stores rows as JSON blobs (snake_cased keys) with full
-- lineage. All business logic lives downstream in SQL.
-- ─────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `@@PROJECT@@.@@RAW@@.raw_rail` (
  feed          STRING    NOT NULL,
  source_file   STRING    NOT NULL,
  ingested_at   TIMESTAMP NOT NULL,
  row_idx       INT64     NOT NULL,
  payload_json  STRING    NOT NULL
)
PARTITION BY DATE(ingested_at);

CREATE TABLE IF NOT EXISTS `@@PROJECT@@.@@RAW@@.raw_road_uk` (
  feed          STRING    NOT NULL,
  source_file   STRING    NOT NULL,
  ingested_at   TIMESTAMP NOT NULL,
  row_idx       INT64     NOT NULL,
  payload_json  STRING    NOT NULL
)
PARTITION BY DATE(ingested_at);

CREATE TABLE IF NOT EXISTS `@@PROJECT@@.@@RAW@@.raw_road_eu` (
  feed          STRING    NOT NULL,
  source_file   STRING    NOT NULL,
  ingested_at   TIMESTAMP NOT NULL,
  row_idx       INT64     NOT NULL,
  payload_json  STRING    NOT NULL
)
PARTITION BY DATE(ingested_at);

-- ── Finance domain feeds (different grain to logistics) ──────────────────────
-- raw_finance_prodcost : production / works cost per tonne (site × commodity × period)
-- raw_finance_mgmt     : management report — working capital + P&L (period × cost centre × line item)
-- Both land here identically (JSON blob + lineage); sp_finance_build shapes them.

CREATE TABLE IF NOT EXISTS `@@PROJECT@@.@@RAW@@.raw_finance_prodcost` (
  feed          STRING    NOT NULL,
  source_file   STRING    NOT NULL,
  ingested_at   TIMESTAMP NOT NULL,
  row_idx       INT64     NOT NULL,
  payload_json  STRING    NOT NULL
)
PARTITION BY DATE(ingested_at);

CREATE TABLE IF NOT EXISTS `@@PROJECT@@.@@RAW@@.raw_finance_mgmt` (
  feed          STRING    NOT NULL,
  source_file   STRING    NOT NULL,
  ingested_at   TIMESTAMP NOT NULL,
  row_idx       INT64     NOT NULL,
  payload_json  STRING    NOT NULL
)
PARTITION BY DATE(ingested_at);
