-- ─────────────────────────────────────────────────────────────────────────
-- dim_feed — the FEED REGISTRY.
--
-- One row per feed, declaring its mode and managing provider. The canonical
-- model joins this so mode/provider come from a single editable source. Adding
-- a new feed (e.g. sea freight) = one row here + one ingest config entry.
--
-- provider = the managing logistics partner who sends the feed (NOT the per-trip
-- sub-carrier, which lives in the carrier column). Labels are editable; the
-- road_eu provider is inferred from the data (P&O Ferrymasters fuel-surcharge
-- labelling) and the road_uk managing partner is to be confirmed by TSUK.
-- ─────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `@@PROJECT@@.@@STG@@.dim_feed` (
  feed_id        STRING,
  mode           STRING,    -- Rail | Road | (future: Sea, Barge)
  provider       STRING,    -- managing partner / data provider
  provider_note  STRING
);

TRUNCATE TABLE `@@PROJECT@@.@@STG@@.dim_feed`;

INSERT INTO `@@PROJECT@@.@@STG@@.dim_feed` (feed_id, mode, provider, provider_note) VALUES
  ('rail',    'Rail', 'DB Cargo',          'TSUK rail freight operator'),
  ('road_uk', 'Road', 'UK Managed Road',   'Direct carriers (54+); managing partner to be confirmed by TSUK'),
  ('road_eu', 'Road', 'P&O Ferrymasters',  'Inferred from fuel-surcharge labelling; confirm with TSUK');
