"""Source config + deterministic Excel→JSON loader.

The ingest service is intentionally "dumb": it does NO semantic mapping. For each
source it reads the configured worksheet, snake_cases every column header, and
emits one JSON object per row. All business logic (typing, cost definitions,
charge-line aggregation) lives in SQL (sql/20_stg_shipments.sql), where it is
visible and testable. This keeps ingest unbreakable on column drift and keeps
the platform evidence-based: raw_ingest is a faithful, lineage-tagged copy of
the source file.
"""

from __future__ import annotations

import io
import re
from typing import Iterator

import pandas as pd

# Feed registry. One entry per feed (file shape / managing provider). mode and
# provider mirror stg.dim_feed; `sheet` is the worksheet to read (None → first).
# Adding a new feed (e.g. sea freight, or a finance domain) = one entry here + one
# raw table (sql/00_raw.sql) + its transform.
#
# The three logistics feeds flow through sp_normalise → mart.movements. The two
# finance feeds (finance_prodcost, finance_mgmt) flow through sp_finance_build into
# their own marts — they are a DIFFERENT grain (production cost / management report),
# not logistics movements. mode/provider are cosmetic lineage tags for finance feeds.
FEED_REGISTRY: dict[str, dict] = {
    "rail":             {"sheet": "FY26", "mode": "Rail",    "provider": "DB Cargo",         "raw_table": "raw_rail"},
    "road_uk":          {"sheet": "Data", "mode": "Road",    "provider": "UK Managed Road",  "raw_table": "raw_road_uk"},
    "road_eu":          {"sheet": "Data", "mode": "Road",    "provider": "P&O Ferrymasters", "raw_table": "raw_road_eu"},
    "finance_prodcost": {"sheet": "Data", "mode": "Finance", "provider": "TSUK Finance",     "raw_table": "raw_finance_prodcost"},
    "finance_mgmt":     {"sheet": "Data", "mode": "Finance", "provider": "TSUK Finance",     "raw_table": "raw_finance_mgmt"},
}

KNOWN_FEEDS = set(FEED_REGISTRY.keys())


def raw_table_for(feed: str) -> str:
    """Per-feed raw table name, e.g. 'raw_road_uk'."""
    return FEED_REGISTRY[feed]["raw_table"]


def snake_case(name: str) -> str:
    """Deterministic header → snake_case. Must match the JSON keys referenced in
    sql/20_stg_shipments.sql exactly.

      'Tonnage (TOPS)'           -> 'tonnage_tops'
      'Total Excl. Cancellation' -> 'total_excl_cancellation'
      'Haulage Revenue '         -> 'haulage_revenue'
      'Order Weight (T)'         -> 'order_weight_t'
      'Revenue_Amount_GBP'       -> 'revenue_amount_gbp'
    """
    s = str(name).strip().lower()
    s = re.sub(r"[^0-9a-z]+", "_", s)   # any run of non-alphanumerics → underscore
    s = re.sub(r"_+", "_", s).strip("_")
    return s


def load_rows(blob: bytes, feed: str) -> Iterator[dict[str, str | None]]:
    """Yield one snake_cased record dict per source row. Values are strings (or
    None); typing happens in SQL."""
    cfg = FEED_REGISTRY.get(feed, {})
    sheet = cfg.get("sheet", 0)
    sheet = sheet if sheet is not None else 0

    try:
        df = pd.read_excel(io.BytesIO(blob), sheet_name=sheet, dtype=str, engine="openpyxl")
    except ValueError:
        # Configured sheet not found — fall back to first sheet.
        df = pd.read_excel(io.BytesIO(blob), sheet_name=0, dtype=str, engine="openpyxl")

    df.columns = [snake_case(c) for c in df.columns]

    for record in df.to_dict(orient="records"):
        yield {
            k: (None if pd.isna(v) else str(v).strip())
            for k, v in record.items()
        }
