"""Ingest service — entry point.

POST /ingest
    body: {"bucket": "...", "object": "landing/<feed>/<file>.xlsx", "feed": "..."}
    flow:
        1. Download object from GCS to memory.
        2. Read the configured worksheet, snake_case headers, emit JSON rows.
        3. Stream rows into the per-feed raw table (raw_rail / raw_road_uk /
           raw_road_eu) with full lineage (feed, source_file, ingested_at, row_idx,
           payload_json).

The service does NO semantic mapping — all transformation logic lives in SQL.
"""

from __future__ import annotations

import json
import logging
import os
import time
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from .bq import load_raw_rows
from .gcs import download_bytes
from .sources import KNOWN_FEEDS, load_rows, raw_table_for

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("ingest")

app = FastAPI(title="Searce TSUK PoC — ingest")

BQ_PROJECT = os.environ["BQ_PROJECT"]
BQ_RAW_DATASET = os.environ["BQ_RAW_DATASET"]
BQ_LOCATION = os.environ.get("BQ_LOCATION", "EU")


class IngestRequest(BaseModel):
    bucket: str = Field(..., description="GCS bucket holding the source file.")
    object: str = Field(..., description="Object path inside the bucket.")
    feed: str = Field(..., description="One of: rail, road_uk, road_eu.")


class IngestResponse(BaseModel):
    feed: str
    object: str
    rows_loaded: int
    raw_table: str
    duration_ms: int


@app.get("/healthz")
def health() -> dict:
    return {"status": "ok"}


@app.post("/ingest", response_model=IngestResponse)
def ingest(req: IngestRequest) -> IngestResponse:
    started = time.perf_counter()

    if req.feed not in KNOWN_FEEDS:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown feed '{req.feed}'. Known: {sorted(KNOWN_FEEDS)}",
        )

    raw_table = f"{BQ_PROJECT}.{BQ_RAW_DATASET}.{raw_table_for(req.feed)}"

    log.info("downloading gs://%s/%s", req.bucket, req.object)
    blob = download_bytes(req.bucket, req.object)

    ingested_at = datetime.now(tz=timezone.utc).isoformat()
    try:
        rows = [
            {
                "feed": req.feed,
                "source_file": req.object,
                "ingested_at": ingested_at,
                "row_idx": i,
                "payload_json": json.dumps(record, ensure_ascii=False, default=str),
            }
            for i, record in enumerate(load_rows(blob, req.feed), start=1)
        ]
    except Exception as e:
        log.exception("failed to read source file")
        raise HTTPException(status_code=422, detail=f"Read failure: {e}") from e

    log.info("loading %d rows into %s", len(rows), raw_table)
    load_raw_rows(table=raw_table, rows=rows)

    duration_ms = int((time.perf_counter() - started) * 1000)
    log.info("ingested feed=%s object=%s rows=%d duration_ms=%d",
             req.feed, req.object, len(rows), duration_ms)

    return IngestResponse(
        feed=req.feed,
        object=req.object,
        rows_loaded=len(rows),
        raw_table=raw_table,
        duration_ms=duration_ms,
    )
