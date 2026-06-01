"""Loader tests.

Two layers:
  1. snake_case() pinned against the real header strings seen in the sample
     files — these MUST match the JSON keys referenced in sql/20_stg_shipments.sql.
  2. End-to-end load against the actual sample workbooks if present locally
     (sample_data/), asserting row counts and that key fields are populated.
"""

from __future__ import annotations

import io
import os

import pandas as pd
import pytest

from app.sources import KNOWN_FEEDS, load_rows, raw_table_for, snake_case

SAMPLE_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "sample_data")

# Filename → feed mapping for the provided samples.
SAMPLE_FILES = {
    "rail":    "Raw Rail Data.xlsx",
    "road_uk": "Raw Road Data Set 1.xlsx",
    "road_eu": "Raw Road Data Set 2 .xlsx",
}


def test_raw_table_routing():
    assert raw_table_for("rail") == "raw_rail"
    assert raw_table_for("road_uk") == "raw_road_uk"
    assert raw_table_for("road_eu") == "raw_road_eu"
    assert KNOWN_FEEDS == {"rail", "road_uk", "road_eu"}

# Keys the SQL layer depends on — pinned so a header-normalisation change that
# would silently break the SQL fails loudly here instead.
EXPECTED_KEYS = {
    "Tonnage (TOPS)": "tonnage_tops",
    "Total Excl. Cancellation": "total_excl_cancellation",
    "Haulage Revenue ": "haulage_revenue",
    "Cancellation Revenue": "cancellation_revenue",
    "Fuel Surcharge": "fuel_surcharge",
    "Date Delivered": "date_delivered",
    "Origin ": "origin",
    "Destination": "destination",
    "TSUK Commodity": "tsuk_commodity",
    "Wagons (Received)": "wagons_received",
    "Order Weight (T)": "order_weight_t",
    "Purchase Cost": "purchase_cost",
    "Sales Cost": "sales_cost",
    "Equipment Type": "equipment_type",
    "Small Coil Test": "small_coil_test",
    "Loading City": "loading_city",
    "Delivery City": "delivery_city",
    "Order Distance": "order_distance",
    "Delivery Date start": "delivery_date_start",
    "Ordering Party": "ordering_party",
    "Carrier Name": "carrier_name",
    "Revenue_Amount_GBP": "revenue_amount_gbp",
    "Gross Weight": "gross_weight",
    "Charge_Type": "charge_type",
    "Actual_Del_Date_Time": "actual_del_date_time",
    "Actual_Col_Date_Time": "actual_col_date_time",
    "Collection_Town": "collection_town",
    "Delivery_Town": "delivery_town",
    "Customer_Name": "customer_name",
    "Code": "code",
    "Modality": "modality",
    "Miles": "miles",
}


@pytest.mark.parametrize("header,expected", EXPECTED_KEYS.items())
def test_snake_case_pinned(header: str, expected: str):
    assert snake_case(header) == expected


def _excel_bytes(rows: list[dict]) -> bytes:
    buf = io.BytesIO()
    pd.DataFrame(rows).to_excel(buf, index=False, engine="openpyxl")
    return buf.getvalue()


def test_load_rows_basic():
    blob = _excel_bytes([{"Order Weight (T)": "3.39", "Purchase Cost": "572.28"}])
    rows = list(load_rows(blob, "road_uk"))
    assert len(rows) == 1
    assert rows[0]["order_weight_t"] == "3.39"
    assert rows[0]["purchase_cost"] == "572.28"


@pytest.mark.parametrize("source,fname", SAMPLE_FILES.items())
def test_against_real_samples(source: str, fname: str):
    path = os.path.join(SAMPLE_DIR, fname)
    if not os.path.exists(path):
        pytest.skip(f"sample not present: {fname}")
    with open(path, "rb") as f:
        blob = f.read()
    rows = list(load_rows(blob, source))
    assert len(rows) > 0
    # row_idx-free record; ensure snake keys present
    sample = rows[0]
    if source == "rail":
        assert "tonnage_tops" in sample and "total_excl_cancellation" in sample
    elif source == "road_uk":
        assert "order_weight_t" in sample and "purchase_cost" in sample
    elif source == "road_eu":
        assert "revenue_amount_gbp" in sample and "charge_type" in sample
