#!/usr/bin/env bash
# Apply BigQuery DDL + stored procedures.
# Substitutes @@PROJECT@@ / @@RAW@@ / @@STG@@ / @@MART@@ placeholders, then
# pipes each file into `bq query`. Idempotent.

set -euo pipefail

PROJECT="${PROJECT:-prj-tsuk-looker-sa-01}"
BQ_PREFIX="${BQ_PREFIX:-searce_poc}"
LOCATION="${LOCATION:-EU}"

RAW="${BQ_PREFIX}_raw"
STG="${BQ_PREFIX}_stg"
MART="${BQ_PREFIX}_mart"

SQL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sql"

substitute() {
  sed \
    -e "s/@@PROJECT@@/${PROJECT}/g" \
    -e "s/@@RAW@@/${RAW}/g" \
    -e "s/@@STG@@/${STG}/g" \
    -e "s/@@MART@@/${MART}/g" \
    "$1"
}

shopt -s nullglob
for f in "$SQL_DIR"/*.sql; do
  echo "→ applying $(basename "$f")"
  substitute "$f" | bq --project_id="$PROJECT" --location="$LOCATION" query --use_legacy_sql=false --quiet
done

echo "✓ BigQuery DDL + procedures applied."
