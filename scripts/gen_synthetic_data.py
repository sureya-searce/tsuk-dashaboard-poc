#!/usr/bin/env python3
"""Synthetic TSUK logistics + finance data generator.

Produces FIVE workbooks under sample_data/ that match the exact feed schemas the
pipeline expects (the human-readable headers here snake_case to the JSON keys the
SQL in sql/ reads). The data is fully synthetic but deliberately shaped so the
workshop narrative lands:

  - rail / road_uk / road_eu : the three logistics feeds. Rail is cheapest per
    tonne, EU road dearest (~6-8x), with carrier concentration and seeded
    cost-leakage anomalies (one per rule R1-R5).
  - finance_prodcost         : production / works cost per tonne (site x commodity
    x period). This is FINANCE'S "cost per tonne" (~£400-600/t) — an order of
    magnitude above the logistics transport "cost per tonne" (~£6-60/t). Same
    words, two true numbers, from one governed model.
  - finance_mgmt             : a management report (working capital + P&L) — the
    Cognos-replacement / "build it" proof point.

The Finance-vs-Logistics divergence is baked in two ways:
  1. Cross-domain (headline): production_cost_per_tonne vs transport_cost_per_tonne.
  2. Within-logistics (secondary): every logistics feed carries a base-freight
     component AND fuel/handling/accessorial components, so a "Finance basis"
     (base freight only) sits below the "Logistics basis" (all-in cost-to-serve).

Deterministic: fixed seed → identical output every run (so reconciliation totals
and demo numbers are stable). Re-run any time with `make gen-data`.

Usage:
    python scripts/gen_synthetic_data.py [--out-dir sample_data] [--seed 42] [--scale 1.0]
"""

from __future__ import annotations

import argparse
import os
from datetime import date, timedelta

import numpy as np
import pandas as pd

# ── Shared reference values ──────────────────────────────────────────────────

COMMODITIES = ["Coil", "Slab", "Plate"]                 # join key shared finance↔logistics
PRODUCTION_SITES = ["Port Talbot", "Llanwern", "Trostre"]

# Financial year FY26 = Apr 2025 → Mar 2026.
FY_MONTHS = [f"2025-{m:02d}" for m in range(4, 13)] + [f"2026-{m:02d}" for m in range(1, 4)]
FY_Q1 = FY_MONTHS[:3]   # road feeds span Q1 only (mirrors the real-feed period mismatch)


def _month_to_date(rng: np.random.Generator, ym: str) -> str:
    """'2025-04' → a random 'YYYY-MM-DD' within that month (day 1-28)."""
    y, m = ym.split("-")
    return f"{y}-{m}-{int(rng.integers(1, 28)):02d}"


def _ts(d: str, rng: np.random.Generator) -> str:
    """date string → 'YYYY-MM-DD HH:MM:SS' timestamp."""
    return f"{d} {int(rng.integers(5, 19)):02d}:{int(rng.integers(0, 60)):02d}:00"


def _money(x: float) -> str:
    return f"{x:.2f}"


def _write(df: pd.DataFrame, path: str, sheet: str) -> None:
    with pd.ExcelWriter(path, engine="openpyxl") as xl:
        df.to_excel(xl, index=False, sheet_name=sheet)
    print(f"  wrote {len(df):>6} rows → {os.path.basename(path)} [{sheet}]")


# ── RAIL ─────────────────────────────────────────────────────────────────────

RAIL_DESTS = ["Tilbury", "Wednesfield", "Corby", "Immingham", "Hartlepool",
              "Shotton", "Wolverhampton", "Scunthorpe", "Dagenham"]
RAIL_ORIGINS = ["Port Talbot", "Llanwern"]


def gen_rail(rng: np.random.Generator, n: int) -> pd.DataFrame:
    rows = []
    for _ in range(n):
        ym = rng.choice(FY_MONTHS)
        wagons = int(rng.integers(2, 23))
        # Normal load: 45-72 t/wagon (capacity 75 → util ~60-96%).
        tonnes = wagons * float(rng.uniform(45, 72))
        cpt_base = float(rng.uniform(5.5, 6.5))          # finance base £/tonne
        haulage = tonnes * cpt_base
        fuel = haulage * float(rng.uniform(0.08, 0.12))
        other = haulage * float(rng.uniform(0.02, 0.05))  # handling / access.
        total_excl = haulage + fuel + other
        rows.append({
            "Date Delivered": _month_to_date(rng, ym),
            "Origin": rng.choice(RAIL_ORIGINS),
            "Destination": rng.choice(RAIL_DESTS),
            "TSUK Commodity": rng.choice(COMMODITIES),
            "Tonnage (TOPS)": _money(tonnes),
            "Wagons (Received)": str(wagons),
            "Haulage Revenue": _money(haulage),
            "Fuel Surcharge": _money(fuel),
            "Other Charges": _money(other),
            "Total Excl. Cancellation": _money(total_excl),
            "Cancellation Revenue": _money(0.0),
        })
    df = pd.DataFrame(rows)
    _seed_rail_anomalies(rng, df)
    return df


def _seed_rail_anomalies(rng: np.random.Generator, df: pd.DataFrame) -> None:
    """Mutate a handful of rows to trigger each anomaly rule (cost stays consistent
    with components so rail reconciliation still ties to source)."""
    idx = list(range(len(df)))
    rng.shuffle(idx)
    take = lambda k: [idx.pop() for _ in range(k)]

    # R3: negative cancellation credit.
    for i in take(8):
        df.at[i, "Cancellation Revenue"] = _money(-float(rng.uniform(500, 6000)))
    # R1: cost-per-tonne spike (inflate all-in ~2.2x; keep total = sum of parts).
    for i in take(12):
        haul = float(df.at[i, "Haulage Revenue"]) * 2.2
        fuel = haul * 0.10
        other = haul * 0.03
        df.at[i, "Haulage Revenue"] = _money(haul)
        df.at[i, "Fuel Surcharge"] = _money(fuel)
        df.at[i, "Other Charges"] = _money(other)
        df.at[i, "Total Excl. Cancellation"] = _money(haul + fuel + other)
    # R4: structural under-utilisation (very light load vs wagons).
    for i in take(30):
        wagons = int(df.at[i, "Wagons (Received)"])
        df.at[i, "Tonnage (TOPS)"] = _money(wagons * float(rng.uniform(10, 24)))
    # R5: utilisation > 100% (overload vs assumed wagon capacity).
    for i in take(8):
        wagons = int(df.at[i, "Wagons (Received)"])
        df.at[i, "Tonnage (TOPS)"] = _money(wagons * float(rng.uniform(80, 95)))
    # R2: cost charged against zero tonnage.
    for i in take(8):
        df.at[i, "Tonnage (TOPS)"] = None


# ── ROAD UK ──────────────────────────────────────────────────────────────────

UK_EQUIP = ["COIL CARRIER", "FLAT", "FLAT/SLIDER - PINS & GOAL POST",
            "H20 1.5 PINS", "28FT TRAILER PINS/GP", "P&P RIGID"]
UK_EQUIP_W = [0.40, 0.25, 0.12, 0.10, 0.08, 0.05]
UK_CAP = {"COIL CARRIER": 29, "FLAT": 29, "FLAT/SLIDER - PINS & GOAL POST": 29,
          "H20 1.5 PINS": 24, "28FT TRAILER PINS/GP": 20, "P&P RIGID": 18}
UK_LOAD_CITIES = ["Port Talbot", "Llanwern", "Shotton", "Trostre", "Corby"]
UK_DEST_CITIES = ["Birmingham", "Sheffield", "Leeds", "Glasgow", "Bristol",
                  "Manchester", "Newcastle", "Nottingham", "Southampton", "Cardiff"]
# ~40 carriers with two dominant (≈33% combined) — a procurement-lever story.
UK_CARRIERS = (["OWENS", "HINGLEY"] +
               [f"Carrier {chr(65 + i)}{j}" for i in range(7) for j in range(6)])[:40]
UK_CARRIER_W = np.array([0.18, 0.15] + [0.67 / 38] * 38)
UK_REGIONS = ["Wales", "Midlands", "North", "Scotland", "South"]
UK_CUSTOMERS = ["JLR", "Caparo", "Liberty Steel", "Nissan", "Hadley Group",
                "Severfield", "Tata Auto", "BCA Group"]


def gen_road_uk(rng: np.random.Generator, n: int) -> pd.DataFrame:
    rows = []
    carriers = np.array(UK_CARRIERS, dtype=object)
    for _ in range(n):
        ym = rng.choice(FY_Q1)
        equip = rng.choice(UK_EQUIP, p=UK_EQUIP_W)
        cap = UK_CAP[equip]
        weight = float(rng.uniform(0.5 * cap, cap))      # util ~50-100%
        base = weight * float(rng.uniform(14, 20))        # finance base freight
        fuel = base * float(rng.uniform(0.08, 0.12))
        handling = base * float(rng.uniform(0.03, 0.06))
        purchase = base + fuel + handling                 # all-in (reconciles)
        rows.append({
            "Delivery Date start": _month_to_date(rng, ym),
            "Loading City": rng.choice(UK_LOAD_CITIES),
            "Delivery City": rng.choice(UK_DEST_CITIES),
            "Region": rng.choice(UK_REGIONS),
            "Commodity": rng.choice(COMMODITIES),
            "Equipment Type": equip,
            "Carrier Name": rng.choice(carriers, p=UK_CARRIER_W),
            "Ordering Party": rng.choice(UK_CUSTOMERS),
            "Order Weight (T)": _money(weight),
            "Order Distance": str(int(rng.integers(20, 400))),
            "Purchase Cost": _money(purchase),
            "Fuel Surcharge": _money(fuel),
            "Handling Charge": _money(handling),
            "Sales Cost": _money(purchase * float(rng.uniform(1.08, 1.20))),
            "Small Coil Test": "INCLUDE" if rng.random() > 0.05 else "EXCLUDE",
        })
    df = pd.DataFrame(rows)
    _seed_uk_anomalies(rng, df)
    return df


def _seed_uk_anomalies(rng: np.random.Generator, df: pd.DataFrame) -> None:
    idx = list(range(len(df)))
    rng.shuffle(idx)
    take = lambda k: [idx.pop() for _ in range(k)]

    # R1: cost spike (keep purchase = base+fuel+handling consistent).
    for i in take(20):
        base = (float(df.at[i, "Purchase Cost"])
                - float(df.at[i, "Fuel Surcharge"])
                - float(df.at[i, "Handling Charge"])) * 2.3
        fuel, handling = base * 0.10, base * 0.04
        df.at[i, "Fuel Surcharge"] = _money(fuel)
        df.at[i, "Handling Charge"] = _money(handling)
        df.at[i, "Purchase Cost"] = _money(base + fuel + handling)
    # R3: negative purchase cost (credit note).
    for i in take(10):
        df.at[i, "Purchase Cost"] = _money(-float(rng.uniform(200, 3000)))
        df.at[i, "Fuel Surcharge"] = _money(0.0)
        df.at[i, "Handling Charge"] = _money(0.0)
    # R4: under-utilised (tiny load on a big-capacity trailer).
    for i in take(40):
        df.at[i, "Equipment Type"] = "COIL CARRIER"
        df.at[i, "Order Weight (T)"] = _money(float(rng.uniform(3, 10)))
    # R5: overloaded vs assumed capacity.
    for i in take(10):
        df.at[i, "Order Weight (T)"] = _money(float(rng.uniform(31, 38)))
    # R2: cost, no weight.
    for i in take(10):
        df.at[i, "Order Weight (T)"] = None


# ── ROAD EU ──────────────────────────────────────────────────────────────────

EU_EQUIP = ["COIL CARRIER", "EUROLINER", "EXTENDER", "FLAT BED"]
EU_EQUIP_W = [0.45, 0.25, 0.15, 0.15]
EU_CAP = {"COIL CARRIER": 27, "EUROLINER": 24, "EXTENDER": 24, "FLAT BED": 24}
EU_ORIGINS = [("Mo i Rana", "NO"), ("Lulea", "SE"), ("Dunkerque", "FR"),
              ("Bremen", "DE"), ("Gent", "BE"), ("Rotterdam", "NL")]
EU_DEST_TOWNS = ["Port Talbot", "Newport", "Liverpool", "Hull", "Teesside", "Belfast"]
EU_HAULIERS = ["P&O Ferrymasters"] + [f"EU Haulier {chr(65 + i)}" for i in range(24)]
EU_CUSTOMERS = ["Tata Strip", "Tata Tubes", "Cogent", "Marcegaglia", "Outokumpu"]


def gen_road_eu(rng: np.random.Generator, n_shipments: int) -> pd.DataFrame:
    """N shipments × ~4 charge lines each. Weight is CONSTANT across a shipment's
    lines (it repeats in the source); cost is the SUM of the lines."""
    rows = []
    hauliers = np.array(EU_HAULIERS, dtype=object)
    h_w = np.array([0.16] + [0.84 / 24] * 24)
    for s in range(n_shipments):
        ym = rng.choice(FY_Q1)
        d = _month_to_date(rng, ym)
        origin_town, origin_cc = EU_ORIGINS[int(rng.integers(0, len(EU_ORIGINS)))]
        equip = rng.choice(EU_EQUIP, p=EU_EQUIP_W)
        cap = EU_CAP[equip]
        weight = float(rng.uniform(0.55 * cap, cap))
        code = f"EU{100000 + s}"
        # Charge lines: Freight (finance base), + Fuel/Maut/Mgmt (logistics-only).
        freight = weight * float(rng.uniform(34, 42))
        lines = [
            ("Freight", freight),
            ("Fuel Surcharge", freight * float(rng.uniform(0.10, 0.16))),
            ("Maut", freight * float(rng.uniform(0.08, 0.14))),
            ("Management Fee", freight * float(rng.uniform(0.05, 0.09))),
        ]
        common = {
            "Code": code,
            "Customer_Name": rng.choice(EU_CUSTOMERS),
            "Charter_Haulier_Name": rng.choice(hauliers, p=h_w),
            "Commodity": rng.choice(COMMODITIES),
            "Collection_Town": origin_town,
            "Delivery_Town": rng.choice(EU_DEST_TOWNS),
            "Collection_Country_Code": origin_cc,
            "Delivery_Country_Code": "GB",
            "Equipment Type": equip,
            "Gross Weight": _money(weight),
            "Miles": str(int(rng.uniform(300, 1200))),
            "Month": f"{ym}-01",
            "Actual_Col_Date_Time": _ts(d, rng),
            "Actual_Del_Date_Time": _ts(d, rng),
        }
        for ct, amt in lines:
            rows.append({**common, "Charge_Type": ct, "Revenue_Amount_GBP": _money(amt)})

    df = pd.DataFrame(rows)
    _seed_eu_anomalies(rng, df)
    return df


def _seed_eu_anomalies(rng: np.random.Generator, df: pd.DataFrame) -> None:
    codes = df["Code"].unique().tolist()
    rng.shuffle(codes)
    pop = lambda k: [codes.pop() for _ in range(k)]

    # R3: a negative rebate line appended to some shipments.
    for code in pop(10):
        proto = df[df["Code"] == code].iloc[0].to_dict()
        proto["Charge_Type"] = "Rebate"
        proto["Revenue_Amount_GBP"] = _money(-float(rng.uniform(200, 1500)))
        df.loc[len(df)] = proto
    # R1: cost spike — multiply every line of the shipment.
    for code in pop(10):
        m = df["Code"] == code
        df.loc[m, "Revenue_Amount_GBP"] = (
            df.loc[m, "Revenue_Amount_GBP"].astype(float) * 2.4).map(_money)
    # R4: under-utilised — drop weight across all the shipment's lines.
    for code in pop(25):
        df.loc[df["Code"] == code, "Gross Weight"] = _money(float(rng.uniform(3, 9)))
    # R5: overloaded.
    for code in pop(8):
        df.loc[df["Code"] == code, "Gross Weight"] = _money(float(rng.uniform(30, 36)))
    # R2: zero weight, cost present.
    for code in pop(8):
        df.loc[df["Code"] == code, "Gross Weight"] = None


# ── FINANCE: production cost per tonne ───────────────────────────────────────

SITE_COMMODITIES = {
    "Port Talbot": ["Coil", "Slab"],
    "Llanwern": ["Coil", "Plate"],
    "Trostre": ["Plate"],
}


def gen_finance_prodcost(rng: np.random.Generator) -> pd.DataFrame:
    rows = []
    for ym in FY_MONTHS:
        for site, comms in SITE_COMMODITIES.items():
            for comm in comms:
                tonnes = float(rng.uniform(20000, 120000))
                cpt = float(rng.uniform(420, 580))          # works cost £/tonne
                works = tonnes * cpt
                rows.append({
                    "Period": ym,
                    "Site": site,
                    "Commodity": comm,
                    "Tonnes Produced": _money(tonnes),
                    "Works Cost (GBP)": _money(works),
                    "Raw Material Cost": _money(works * 0.55),
                    "Energy Cost": _money(works * 0.20),     # EAF-era energy focus
                    "Labour Cost": _money(works * 0.12),
                    "Overhead Cost": _money(works * 0.13),
                    "Standard Cost per Tonne": _money(cpt * float(rng.uniform(0.95, 1.05))),
                })
    return pd.DataFrame(rows)


# ── FINANCE: management report (working capital + P&L) ───────────────────────

MGMT_CENTRES = ["Strip Products", "Long Products", "Distribution", "Group"]
# (line item, category, base £ magnitude, sign)
MGMT_LINES = [
    ("Inventory",         "Working Capital",  300e6,  +1),
    ("Trade Receivables", "Working Capital",  220e6,  +1),
    ("Trade Payables",    "Working Capital",  180e6,  -1),
    ("Revenue",           "P&L",              480e6,  +1),
    ("COGS",              "P&L",              430e6,  -1),
    ("EBITDA",            "P&L",               35e6,  +1),
]


def gen_finance_mgmt(rng: np.random.Generator) -> pd.DataFrame:
    rows = []
    for ym in FY_MONTHS:
        for centre in MGMT_CENTRES:
            for item, cat, base, sign in MGMT_LINES:
                amt = sign * base * float(rng.uniform(0.8, 1.2))
                rows.append({
                    "Period": ym,
                    "Cost Centre": centre,
                    "Line Item": item,
                    "Category": cat,
                    "Amount (GBP)": _money(amt),
                    "Plan Amount (GBP)": _money(amt * float(rng.uniform(0.9, 1.1))),
                })
    return pd.DataFrame(rows)


# ── Driver ───────────────────────────────────────────────────────────────────

FEEDS = [
    ("Raw Rail Data.xlsx",        "FY26", lambda rng, sc: gen_rail(rng, int(4000 * sc))),
    ("Raw Road Data Set 1.xlsx",  "Data", lambda rng, sc: gen_road_uk(rng, int(15000 * sc))),
    ("Raw Road Data Set 2 .xlsx", "Data", lambda rng, sc: gen_road_eu(rng, int(4000 * sc))),
    ("Production Cost Data.xlsx", "Data", lambda rng, sc: gen_finance_prodcost(rng)),
    ("Management Report.xlsx",    "Data", lambda rng, sc: gen_finance_mgmt(rng)),
]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out-dir", default=os.path.join(os.path.dirname(__file__), "..", "sample_data"))
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--scale", type=float, default=1.0, help="scale logistics row counts")
    args = ap.parse_args()

    out = os.path.abspath(args.out_dir)
    os.makedirs(out, exist_ok=True)
    print(f"Generating synthetic data → {out}  (seed={args.seed}, scale={args.scale})")

    for offset, (fname, sheet, builder) in enumerate(FEEDS):
        # Stable per-feed seed (no hash() — its randomisation would break determinism).
        rng = np.random.default_rng(args.seed + 1000 * (offset + 1))
        df = builder(rng, args.scale)
        _write(df, os.path.join(out, fname), sheet)

    print("Done. Upload with: make upload-files")


if __name__ == "__main__":
    main()
