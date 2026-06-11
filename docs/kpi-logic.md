# KPI & Transformation Logic

Every metric, its exact formula, and its source column — so any number on a
dashboard or from Conversational Analytics can be traced to data. Assumptions
are called out explicitly.

## Domain-owned medallion (where things live)

```
raw  (bronze, shared)   per-feed JSON landing
stg  (silver, shared)   clean conformed facts (shipments, production, management)
                        + conformed dims (commodity, site, calendar, feed, capacity)
core (gold, shared)     conformed facts (movements, production_cost) + GOVERNED KPIs
                        (cost_per_tonne) + reconciliation + data_catalog
finance      (gold, Finance-owned)       cost_analysis, management_report
supplychain  (gold, SC-owned)            utilisation, lane_performance, carrier_spend, anomalies
```

The **dataset is the ownership boundary** (per-team IAM). Conformed facts and any
**cross-team KPI live once in `core`**; teams build their own views on top but read
the same governed definitions. `core.data_catalog` records owner + shared flag per table.

## The governed cross-team KPI — "cost per tonne"

One metric name, three legitimate readings from the **same source of truth**
(`core.cost_per_tonne`, by commodity × period):

| Basis | Definition | Source | Typical (synthetic) |
|---|---|---|---|
| **Finance** | production / works cost ÷ tonnes produced | `core.production_cost` | ~£500 / t |
| **Logistics** | all-in transport cost ÷ tonnes moved | `core.movements` | ~£7–50 / t |
| **Landed (governed)** | Finance + Logistics, signed off across functions | both | production + transport |

This is the workshop's spine: *same word, different numbers, both correct* — resolved
by defining each basis explicitly in the Looker semantic layer and blessing **landed**
as the governed answer Conversational Analytics inherits.

**Secondary (within transport):** even logistics cost splits — Finance counts base
contracted freight (`finance_cost_gbp`), Logistics counts all-in cost-to-serve
(`cost_gbp`). Per feed: rail `finance_cost_gbp` = haulage; road_eu = Freight charge
lines; road_uk = purchase − fuel − handling.

## Canonical grain

One row in `mart.movements` = one **movement** (trip):
- rail: one rail delivery (source row)
- road_uk: one **leg** / cost event (source row)
- road_eu: one **shipment** (aggregated from ~4.2 charge lines)

## Dimensions (provider / mode / trip)

The model is built around dimensions, not split tables — so a new carrier or even
a new mode never changes the schema:

| Dimension | Meaning | Source | Cardinality (sample) |
|---|---|---|---|
| `feed` | file shape / managing partner feed | landing folder | 3 (`rail`, `road_uk`, `road_eu`) |
| `mode` | Rail / Road (future: Sea, Barge) | `stg.dim_feed` | 2 |
| `provider` | managing logistics partner | `stg.dim_feed` (editable) | 3 |
| `carrier` | the company doing the trip | row column | **116** (115 on road) |
| `trip_type` | Domestic / Cross-border | origin↔dest country | 2 |
| trip (grain) | the individual movement | one row | 142,090 |

Every "by provider / by mode / by carrier / domestic-vs-import" question is a
`GROUP BY` over the one fact table. Validated slices on the sample data:
mode (Rail £27.1M / Road £54.3M), provider (DB Cargo £27.1M, UK Managed Road
£36.4M, P&O Ferrymasters £17.9M), trip_type (Cross-border £17.9M / Domestic
£63.5M), carrier (top: OWENS £6.5M, HINGLEY £6.3M).

A new feed (e.g. sea freight) = one row in `stg.dim_feed` + one entry in the
ingest `FEED_REGISTRY` + a `raw_<feed>` table — no model redesign.

## Cost-to-TSUK definition (per feed)

| Feed | Cost column used | Why | Excluded |
|---|---|---|---|
| rail | `total_excl_cancellation` | Clean freight cost; reconciles to haulage+handling+other+fuel | `cancellation_revenue` tracked separately as `cancellation_gbp` |
| road_uk | `purchase_cost` | What TSUK pays the carrier (procurement) | `sales_cost` (onward charge, not a logistics cost) |
| road_eu | `SUM(revenue_amount_gbp)` per shipment | Net of all charge lines: Freight + Maut + Mgmt Fee + Fuel Surcharge (often negative) | — |

**Validation:** rail cost components sum to `Total` with **0 mismatches**;
`Total − Cancellation = Total Excl. Cancellation` with **0 mismatches** (verified
on sample).

## Tonnage

| Feed | Source column | Note |
|---|---|---|
| rail | `tonnage_tops` | TOPS tonnage |
| road_uk | `order_weight_t` | Per leg |
| road_eu | `MAX(gross_weight)` per shipment | Weight repeats across charge lines — MAX, never SUM |

## Derived metrics

| Metric | Formula | Notes |
|---|---|---|
| `cost_per_tonne` | `cost_gbp / NULLIF(tonnes,0)` | NULL when no tonnage |
| `cost_per_load` (agg) | `SUM(cost_gbp) / COUNT(*)` | Movement = load |
| `cost_per_tonne` (agg) | `SUM(cost_gbp) / SUM(tonnes)` | Weighted, not avg-of-ratios |
| `utilisation_pct` | `tonnes / NULLIF(capacity_tonnes,0) * 100` | **Assumption-based** (see below) |

## Capacity (the one assumption)

No feed carries vehicle/wagon capacity, so utilisation needs a seeded lookup
(`stg.dim_capacity`), editable with TSUK's real fleet spec:

| Source | Capacity basis | Default |
|---|---|---|
| rail | per-wagon payload × `wagons_received` | 75 t/wagon |
| road_uk | by `equipment_type` | 18–29 t (29 default) |
| road_eu | by `equipment_type` | 24–27 t (25 default) |

Surfaced in `mart.assumptions`; every utilisation figure is labelled as
assumption-based in the narrative and dashboards.

## Anomaly rules (deterministic SQL — `mart.anomalies`)

| Rule | Condition | Meaning |
|---|---|---|
| R1 | `cost_per_tonne ≥ 1.5 × lane median` | Cost spike on a lane |
| R2 | `has_cost AND NOT has_tonnes` | Paying for nothing |
| R3 | `cost_gbp < 0 OR cancellation_gbp < 0` | Credit / cancellation |
| R4 | `utilisation_pct < 40` (in range) | Structural under-utilisation |
| R5 | `utilisation_pct > 100` | Capacity-assumption / data error — flag, don't trust |

`impact_score = |cost_gbp| × (1 + |deviation|)` → Top-10 ranking.

## Lineage

Every `mart.movements` row carries `source`, `source_file`, `movement_id`
(deterministic `FARM_FINGERPRINT`), so any figure drills back to the originating
file and row.

## Known PoC simplifications (stated, not hidden)

- **road_uk grain is per-leg.** A multi-leg order's tonnage appears on each leg;
  "total tonnes" at order level would double-count. Cost-per-tonne per leg is
  unaffected. Flagged for productionisation.
- **Capacity is assumed** (above).
- **Commodity** only present for rail (`tsuk_commodity`); road feeds have none.
- Periods differ (rail full FY26, road FY26 Q1) — compare within period, not
  across totals, unless normalised.
