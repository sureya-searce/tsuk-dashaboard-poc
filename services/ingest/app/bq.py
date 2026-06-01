"""BigQuery loader for the per-feed raw tables (raw_rail / raw_road_uk /
raw_road_eu).

For a given source_file we first DELETE any prior rows for that file (idempotent
re-ingest), then load via a load job (WRITE_APPEND). A load job — not streaming
inserts — because files can be large (road_uk ≈ 124k rows); load jobs are free
and batch-sized, and rows are queryable once the job completes, which is what
the Workflow waits on before the SQL transforms.
"""

from __future__ import annotations

from typing import Any

from google.cloud import bigquery

_client: bigquery.Client | None = None


def _get_client() -> bigquery.Client:
    global _client
    if _client is None:
        _client = bigquery.Client()
    return _client


def load_raw_rows(table: str, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return

    client = _get_client()
    source_file = rows[0]["source_file"]

    # Idempotent re-ingest: clear any previous rows for this exact file.
    client.query(
        f"DELETE FROM `{table}` WHERE source_file = @sf",
        job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("sf", "STRING", source_file)]
        ),
    ).result()

    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        schema=[
            bigquery.SchemaField("feed", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("source_file", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("ingested_at", "TIMESTAMP", mode="REQUIRED"),
            bigquery.SchemaField("row_idx", "INT64", mode="REQUIRED"),
            bigquery.SchemaField("payload_json", "STRING", mode="REQUIRED"),
        ],
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
    )
    client.load_table_from_json(rows, table, job_config=job_config).result()
