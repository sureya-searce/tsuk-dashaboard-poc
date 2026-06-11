#!/usr/bin/env bash
# Apply BigQuery DDL + stored procedures for the domain-owned medallion.
# Creates the datasets (idempotent), substitutes the dataset placeholders, then
# pipes each SQL file into `bq query`. Idempotent (CREATE OR REPLACE everywhere).
#
# Datasets (ownership boundaries):
#   _raw  bronze (shared)        _stg  silver (shared conformed)
#   _core gold (shared governed) _finance / _supplychain  gold (team-owned)

set -euo pipefail

PROJECT="${PROJECT:-prj-tsuk-looker-sa-01}"
BQ_PREFIX="${BQ_PREFIX:-searce_poc}"
LOCATION="${LOCATION:-EU}"

RAW="${BQ_PREFIX}_raw"
STG="${BQ_PREFIX}_stg"
CORE="${BQ_PREFIX}_core"
FINANCE="${BQ_PREFIX}_finance"
SC="${BQ_PREFIX}_supplychain"

SQL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sql"

# Ensure datasets exist (no-op if Terraform already created them).
for ds in "$RAW" "$STG" "$CORE" "$FINANCE" "$SC"; do
  bq --project_id="$PROJECT" --location="$LOCATION" mk --dataset --force "$PROJECT:$ds" >/dev/null 2>&1 || true
done

substitute() {
  sed \
    -e "s/@@PROJECT@@/${PROJECT}/g" \
    -e "s/@@RAW@@/${RAW}/g" \
    -e "s/@@STG@@/${STG}/g" \
    -e "s/@@CORE@@/${CORE}/g" \
    -e "s/@@FINANCE@@/${FINANCE}/g" \
    -e "s/@@SC@@/${SC}/g" \
    "$1"
}

shopt -s nullglob
for f in "$SQL_DIR"/*.sql; do
  echo "→ applying $(basename "$f")"
  substitute "$f" | bq --project_id="$PROJECT" --location="$LOCATION" query --use_legacy_sql=false --quiet
done

echo "✓ BigQuery DDL + procedures applied (raw/stg/core/finance/supplychain)."
