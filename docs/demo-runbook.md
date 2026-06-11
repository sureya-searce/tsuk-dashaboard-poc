# TSUK Logistics PoC — Demo Runbook

Everything you need to run the live demo confidently: where to land files, what
happens at each layer, the numbers to quote, the assumptions to be honest about,
and how to recover if something misbehaves.

> Read `docs/narrative.md` for the story; this is the operational companion.

---

## 0. One-line mental model

> A logistics file dropped into a Cloud Storage folder triggers a fully automated
> pipeline that lands it in BigQuery, reshapes three differently-shaped feeds into
> one model, computes Finance & Supply-Chain KPIs and cost-leakage anomalies, and
> proves every number ties back to the source file — with no manual steps.

```
drop file → GCS → Eventarc → Cloud Workflow → Cloud Run (ingest) → BigQuery
            (searce-poc-gcs-trigger)  (searce-poc-pipeline)
            (sp_normalise → sp_finance_stage → sp_build_core
               → sp_build_finance → sp_build_supplychain → sp_data_quality)
```

---

## 1. Where to land the files

**Project:** `infraappsandbox`  ·  **Bucket:** `gs://infraappsandbox-tsuk-logistics-poc-euw2`  (europe-west2)

**Path rule — this is the only thing that matters:**

```
landing/<feed>/<anything>.xlsx
```

- `<feed>` MUST be one of: **`rail`**, **`road_uk`**, **`road_eu`**, **`finance_prodcost`**, **`finance_mgmt`**
- File MUST end in `.xlsx`
- Exactly one sub-folder deep (`landing/rail/file.xlsx`, not `landing/rail/2025/file.xlsx`)

| Feed | Drop the file here | Sample file |
|---|---|---|
| Rail (DB Cargo) | `landing/rail/` | `Raw Rail Data.xlsx` |
| UK road | `landing/road_uk/` | `Raw Road Data Set 1.xlsx` |
| European road | `landing/road_eu/` | `Raw Road Data Set 2 .xlsx` |
| Finance — production cost | `landing/finance_prodcost/` | `Production Cost Data.xlsx` |
| Finance — management report | `landing/finance_mgmt/` | `Management Report.xlsx` |

> Files are **synthetic** — regenerate any time with `make gen-data`. `make upload-files`
> drops all five. Deploy a fresh sandbox project in one shot with `make bootstrap`.

**How to drop a file (two ways):**

```bash
# CLI
gcloud storage cp "sample_data/Raw Rail Data.xlsx" \
  gs://infraappsandbox-tsuk-logistics-poc-euw2/landing/rail/

# or: GCS console → bucket → landing/rail/ → Upload
# or: make trigger SOURCE=rail FILE="sample_data/Raw Rail Data.xlsx"
```

**Demo tip — drop them one at a time** (rail → road_uk → road_eu), waiting a few
seconds between each. Simultaneous drops work too (tested), but sequential keeps
the on-screen story clean and avoids a transient mid-rebuild view. If you ever
doubt the state after a burst, run the "refresh" command in §7.

---

## 2. Watch it run (what to show on screen)

```bash
# List recent workflow executions (state + time)
gcloud workflows executions list searce-poc-pipeline --location=europe-west2 \
  --limit=5 --format="table(name.basename(), state, startTime)"

# Describe the latest execution's result (shows rows ingested + BQ job ids)
gcloud workflows executions describe \
  $(gcloud workflows executions list searce-poc-pipeline --location=europe-west2 --limit=1 --format="value(name)") \
  --location=europe-west2 --format="value(result)"
```

A healthy run returns `status: OK` with `ingest.rows_loaded` and six BigQuery
job references (normalise, finance_stage, build_core, build_finance,
build_supplychain, data_quality). Ingest takes a few seconds per feed
(road_uk is the largest at ~15k rows).

The **GCP Console → Workflows → searce-poc-pipeline → Executions** view is the
nicest thing to show live — each file drop produces its own execution you can
click into and watch step through.

---

## 3. What each layer does (explain it in plain English)

### RAW (`searce_poc_raw`) — "a faithful copy of what arrived"
- Three tables: `raw_rail`, `raw_road_uk`, `raw_road_eu` — one per feed.
- The ingest service does **no business logic**. It reads the spreadsheet, lower-cases
  the column names, and stores **each row as a JSON blob** with lineage (which file,
  which row, when). *Why:* the three feeds have wildly different columns (29–34 each),
  and one is charge-line grain. Storing JSON means the pipeline never breaks on a
  column rename, and every transformation rule lives in SQL where it's visible.

### STG (`searce_poc_stg`) — "make three shapes into one"
- `sp_normalise` reshapes all three feeds into **one canonical table, `shipments`**:
  one row per movement, same columns for every feed (date, lane, tonnes, cost, carrier,
  utilisation…).
- The hard reconciliation it does:
  - **rail**: one source row = one movement (pass through).
  - **road_uk**: one source row = one leg (pass through at leg grain).
  - **road_eu**: ~4 billing lines per shipment → **aggregated** into one shipment
    (sum the cost lines, take the weight once).
- Two dimension tables drive it: `dim_feed` (mode + provider per feed) and
  `dim_capacity` (vehicle/wagon capacity assumptions for utilisation).

- `sp_finance_stage` cleans the two finance feeds into **`production`** (works cost by
  site×commodity×period) and **`management`** (working capital + P&L).
- Conformed dimensions every team joins on: `dim_commodity`, `dim_site`, `dim_calendar`,
  plus `dim_feed` and `dim_capacity`.

### GOLD — split by ownership (the answers)
- **`searce_poc_core`** (shared, governed): `sp_build_core` builds the conformed facts
  **`movements`** + **`production_cost`**, the **governed cross-team KPI `cost_per_tonne`**
  (finance | transport | landed), and **`data_catalog`** (who owns what). `sp_data_quality`
  builds the receipts: **`reconciliation`**, `dq_flags`, `assumptions`.
- **`searce_poc_finance`** (Finance-owned): `sp_build_finance` → `cost_analysis` (production
  cost/t + variance), `management_report` (working capital + P&L vs plan).
- **`searce_poc_supplychain`** (SC-owned): `sp_build_supplychain` → `utilisation`,
  `lane_performance`, `carrier_spend`, `anomalies` (Top-N cost leakage).
- **The point:** any cross-team KPI is defined ONCE in `core`; each team's gold + Looker
  model inherits it. The dataset is the IAM/ownership boundary.

---

## 4. The numbers to quote (all reconciled to source — see §6)

> ⚠️ The figures in this section are from the **original client data** and are kept for
> shape/context only. The sandbox runs **synthetic** data (`make gen-data`) with different
> totals (e.g. rail ≈ £19M, EU road ≈ £4M, production ≈ £500/t). **Always reproduce live**
> from `queries/sample_queries.sql` — the ratios and story hold; the absolute £ differ.

Sample data = **£81.42M** of logistics spend, **142,090** movements (rail = full
FY26; road feeds = FY26 Q1). Every figure below is on the **full-feed basis** — it
ties exactly to the reconciliation (§6) and each row is internally consistent
(Cost ÷ tonnes = Cost/tonne).

| Feed | Movements | Cost | Tonnes | Cost / tonne |
|---|---|---|---|---|
| Rail (DB Cargo) | 3,401 | £27,124,697 | 4,130,624 | **£6.57** |
| UK road | 124,045 | £36,367,196 | 1,785,196 | £20.37 |
| EU road (cross-border) | 14,644 | £17,930,073 | 324,146 | **£55.31** |
| **Total** | **142,090** | **£81,421,966** | | |

**The killer line (airtight):** *European road freight costs **8.4× per tonne**
what rail does — **£55.31 vs £6.57**.* This is the clean comparison: rail is at
movement grain and EU road at shipment grain, so they're like-for-like, and both
reconcile to source. The single most actionable cost fact for an import-era
supply chain.

> ⚠️ **If asked about UK road's £20.37/tonne:** UK road is **leg-grain** (a multi-leg
> order's tonnage is counted on each leg), so this is a *leg-level* average and
> understates true per-consignment cost. That's exactly why the headline comparison
> is **rail vs EU road** — both clean grains. Don't headline the UK road £/tonne.

**Second insight (verified):** two UK road carriers — **OWENS (£6.49M)** and
**HINGLEY (£6.30M)** = **£12.79M, ~35% of UK road spend** — out of **54** distinct
UK road carriers. A clear procurement / negotiation lever.

**Supply Chain (assumption-based — see §5):** of in-scope loads with a valid
utilisation reading, **mean ≈ 69%** and **~29% run below 60%** of assumed capacity
(13% below 40%) → consolidation opportunity. Always say "based on assumed capacity."

> Don't memorise these — they're live. Reproduce on screen with
> `queries/sample_queries.sql` (Finance Q1 = cost/load by mode·trip; reconciliation
> Q1 = the £0-delta proof; carrier_monthly Q1 = OWENS/HINGLEY). The exact killer
> ratio: `SELECT SAFE_DIVIDE(eu,rail) ...` over the two feeds' cost-per-tonne.

---

## 5. Assumptions — be upfront about these

Saying these out loud *builds* credibility; the platform is explicit about them
(`mart.assumptions`).

1. **Cost-to-TSUK definition per feed** (documented in `docs/kpi-logic.md`):
   - rail = `Total Excl. Cancellation` (cancellation tracked separately)
   - road_uk = `Purchase Cost` (what we pay the carrier, **not** the onward Sales Cost)
   - road_eu = **sum** of all charge lines (Freight + Maut + Mgmt Fee + Fuel Surcharge…)
2. **Capacity is assumed.** No feed carries vehicle/wagon capacity, so utilisation
   uses seeded estimates in `stg.dim_capacity` (e.g. UK artic ≈ 29t, rail wagon ≈ 75t).
   **Editable** — replace with TSUK's real fleet spec and utilisation sharpens instantly.
   Every utilisation figure should be described as "based on assumed capacity."
3. **Provider labels** are partly inferred: rail = DB Cargo (known); EU road =
   P&O Ferrymasters (inferred from the fuel-surcharge labelling); UK road managing
   partner = to be confirmed by TSUK. Sub-carriers (116 across all feeds, 115 on road) come straight from
   the data.
4. **road_uk is leg-grain.** A multi-leg order's tonnage appears on each leg, so
   "total tonnes" at order level would double-count; cost-per-tonne per leg is exact.
5. **road_eu dates** fall back delivery → collection → month so no shipment is dropped.
6. **Anomaly detection is rule-based** (deterministic SQL), not ML.

---

## 6. The "prove it" moment (evidence-based by design)

This is the trust-builder. Run:

```sql
SELECT feed, raw_rows, movements,
       ROUND(source_cost_gbp,0) source, ROUND(computed_cost_gbp,0) computed,
       ROUND(cost_delta,2) delta
FROM `infraappsandbox.searce_poc_core.reconciliation` ORDER BY feed;
```

Expected — **delta £0 on every feed**:

| feed | source | computed | delta |
|---|---|---|---|
| rail | 27,124,697 | 27,124,697 | 0 |
| road_uk | 36,367,196 | 36,367,196 | 0 |
| road_eu | 17,930,073 | 17,930,073 | 0 |

Say: *"The computed totals are checked against control totals taken straight from
the source columns — independent of our transformation logic. They match to the
penny. And when Conversational Analytics answers a question, the number comes from
a SQL aggregation over these rows, not from the model's imagination."*

---

## 7. Recover / reset (if something looks off)

```bash
# Re-run the whole transform once (idempotent) — fixes any transient mid-race view
for p in searce_poc_stg.sp_normalise searce_poc_stg.sp_finance_stage \
         searce_poc_core.sp_build_core searce_poc_finance.sp_build_finance \
         searce_poc_supplychain.sp_build_supplychain searce_poc_core.sp_data_quality; do
  bq query --use_legacy_sql=false --location=EU "CALL \`infraappsandbox.$p\`()"
done

# Full blank slate (re-demo from scratch): empty data + clear landing files
make cleanup    # truncate-bq + delete-gcs-files

# Full clean reset of one feed: clear its raw rows then re-drop
bq query --use_legacy_sql=false --location=EU \
  'DELETE FROM `infraappsandbox.searce_poc_raw.raw_rail` WHERE TRUE'
```

---

## 8. Failure modes (so nothing surprises you on stage)

| Someone does this | What happens | Your line |
|---|---|---|
| Drops into wrong folder / not a known feed (`landing/foo/…`) | Workflow returns **SKIPPED** with a reason; nothing ingested | "It only accepts the three known feeds; anything else is safely ignored." |
| Drops a non-Excel / corrupt file as `.xlsx` | Ingest returns 422 → execution **FAILS** loudly; nothing reaches BigQuery | "Bad files fail fast and visibly — they can't pollute the data." |
| Drops a valid Excel with **wrong columns** into a real feed folder | Ingested to raw, but rows produce no date/cost → **dropped at normalise**; mart and reconciliation unaffected (you'll see `raw_rows > movements`) | "Malformed rows can't corrupt the numbers; the reconciliation gap flags them." |
| Drops all 3 at once | 3 concurrent executions; final state correct & reconciled (tested) | "Each file is its own independent run." |

**Production hardening (next-step framing, not built):** turn the silent
drop of wrong-column files into an explicit `quarantine/` rejection, and alert when
`raw_rows − movements` exceeds a threshold.

---

## 9. Looker — one model, explores grouped by owner

One LookML model (`lookml/models/searce-tsuk-poc.model.lkml`) on the
**Searce-Looker → infraappsandbox** connection (set the exact `connection:` name in the
model file). One connection serves all datasets — views use fully-qualified table names.
Explores are grouped by owner:
- **Governed Core** — `cost_per_tonne` (finance | transport | landed), `movements`,
  `production_cost`, `reconciliation`, `data_catalog`.
- **Finance** — `cost_analysis`, `management_report`.
- **Supply Chain** — `utilisation`, `lane_performance`, `carrier_spend`, `anomalies`.

(Production posture: split into per-team models with model-level access grants —
mention it, don't build it for the workshop.)

Build the two persona dashboards (Finance/Richard Williams, Supply Chain/Dan Jones) + a
shared KPI-governance tile from `core.cost_per_tonne`.

**Conversational Analytics — the workshop moment** (grounded on the governed measures):
1. "What's our **cost per tonne**?" → the governed **landed** answer; turn on *show reasoning*
   so it cites the definition.
2. "Show **finance vs logistics cost per tonne by commodity**." → both bases, consistent, one model.
3. "**Working capital** this period vs plan." (Finance)
4. "Where are we paying for **loads under 60% utilised**?" (Supply Chain)
5. "Which **carriers** concentrate our spend?" (Supply Chain)

The `warm` Cloud Run service + cache-warm workflow step remain commented in code, ready to
re-enable for cache warming.

---

## 10. Pre-demo checklist

- [ ] `gcloud config configurations activate infraappsandbox` (project `infraappsandbox`)
- [ ] Workflow active: `gcloud workflows describe searce-poc-pipeline --location=europe-west2 --format='value(state)'` → `ACTIVE`
- [ ] Trigger active: `gcloud eventarc triggers describe searce-poc-gcs-trigger --location=europe-west2 --format='value(name)'`
- [ ] Ingest healthy: `gcloud run services describe searce-poc-ingest --region=europe-west2 --format='value(status.url)'`
- [ ] Reconciliation clean (run §6 query → all deltas 0)
- [ ] Sample files present in `sample_data/`
- [ ] Console tabs open: Workflows executions, BigQuery (saved `sample_queries.sql`)
