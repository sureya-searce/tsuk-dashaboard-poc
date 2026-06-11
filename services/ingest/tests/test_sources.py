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

# Filename → feed mapping for the generated samples (scripts/gen_synthetic_data.py).
SAMPLE_FILES = {
    "rail":             "Raw Rail Data.xlsx",
    "road_uk":          "Raw Road Data Set 1.xlsx",
    "road_eu":          "Raw Road Data Set 2 .xlsx",
    "finance_prodcost": "Production Cost Data.xlsx",
    "finance_mgmt":     "Management Report.xlsx",
}


def test_raw_table_routing():
    assert raw_table_for("rail") == "raw_rail"
    assert raw_table_for("road_uk") == "raw_road_uk"
    assert raw_table_for("road_eu") == "raw_road_eu"
    assert raw_table_for("finance_prodcost") == "raw_finance_prodcost"
    assert raw_table_for("finance_mgmt") == "raw_finance_mgmt"
    assert KNOWN_FEEDS == {"rail", "road_uk", "road_eu", "finance_prodcost", "finance_mgmt"}

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
    # Added for the divergence + finance feeds.
    "Commodity": "commodity",
    "Handling Charge": "handling_charge",
    "Works Cost (GBP)": "works_cost_gbp",
    "Tonnes Produced": "tonnes_produced",
    "Standard Cost per Tonne": "standard_cost_per_tonne",
    "Period": "period",
    "Site": "site",
    "Raw Material Cost": "raw_material_cost",
    "Energy Cost": "energy_cost",
    "Cost Centre": "cost_centre",
    "Line Item": "line_item",
    "Category": "category",
    "Amount (GBP)": "amount_gbp",
    "Plan Amount (GBP)": "plan_amount_gbp",
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
    # Header-drift guard: every JSON key the SQL layer reads must be present after
    # snake_case normalisation (see sql/20_stg_shipments.sql, sql/60_finance.sql).
    required = {
        "rail": {"tonnage_tops", "total_excl_cancellation", "haulage_revenue",
                 "fuel_surcharge", "date_delivered", "tsuk_commodity", "wagons_received"},
        "road_uk": {"order_weight_t", "purchase_cost", "fuel_surcharge", "handling_charge",
                    "equipment_type", "carrier_name", "small_coil_test", "commodity"},
        "road_eu": {"revenue_amount_gbp", "charge_type", "gross_weight", "code",
                    "collection_country_code", "delivery_country_code", "commodity"},
        "finance_prodcost": {"period", "site", "commodity", "tonnes_produced",
                             "works_cost_gbp", "standard_cost_per_tonne"},
        "finance_mgmt": {"period", "cost_centre", "line_item", "category",
                         "amount_gbp", "plan_amount_gbp"},
    }[source]
    missing = required - set(rows[0].keys())
    assert not missing, f"{source}: missing keys {missing}"
