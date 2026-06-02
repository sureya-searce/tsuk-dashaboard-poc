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
            (searce-poc-gcs-trigger)  (searce-poc-pipeline)  (sp_normalise → sp_unify → sp_anomalies → sp_data_quality)
```

---

## 1. Where to land the files

**Bucket:** `gs://tsuk-searce-dashboard-poc-euw2`  (europe-west2)

**Path rule — this is the only thing that matters:**

```
landing/<feed>/<anything>.xlsx
```

- `<feed>` MUST be one of: **`rail`**, **`road_uk`**, **`road_eu`**
- File MUST end in `.xlsx`
- Exactly one sub-folder deep (`landing/rail/file.xlsx`, not `landing/rail/2025/file.xlsx`)

| Feed | Drop the file here | Sample file |
|---|---|---|
| Rail (DB Cargo) | `landing/rail/` | `Raw Rail Data.xlsx` |
| UK road | `landing/road_uk/` | `Raw Road Data Set 1.xlsx` |
| European road | `landing/road_eu/` | `Raw Road Data Set 2 .xlsx` |

**How to drop a file (two ways):**

```bash
# CLI
gcloud storage cp "sample_data/Raw Rail Data.xlsx" \
  gs://tsuk-searce-dashboard-poc-euw2/landing/rail/

# or: GCS console → bucket → landing/rail/ → Upload
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

A healthy run returns `status: OK` with `ingest.rows_loaded` and four BigQuery
job references (normalise, unify, anomalies, data_quality). Ingest takes ~8s for
rail, longer for road_uk (124k rows).

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

### MART (`searce_poc_mart`) — "the answers"
- `sp_unify` builds the single source-of-truth fact table **`movements`**, plus
  rollups: `lane_monthly`, `carrier_monthly`, `kpi_monthly`.
- `sp_anomalies` builds **`anomalies`** — rule-based cost-leakage, ranked by £ impact.
- `sp_data_quality` builds the **audit layer**: `reconciliation` (computed totals vs
  source), `dq_flags` (every excluded/suspect row), `assumptions` (the non-source inputs).

---

## 4. The numbers to quote (all reconciled to source — see §6)

Sample data = £81.4M of logistics spend, 142,090 movements (rail = full FY26;
road feeds = FY26 Q1).

| Feed | Movements | Cost | Cost / tonne |
|---|---|---|---|
| Rail (DB Cargo) | 3,401 | £27.12M | **£6.57** |
| UK road (domestic) | 124,045 | £36.37M | £15.33 |
| EU road (cross-border) | 14,644 | £17.93M | **£55.37** |

**The killer line:** *European road freight costs ~8× per tonne what rail does
(£55 vs £6.57)* — the single most actionable cost fact for an import-era supply chain.

**Second insight:** two UK carriers (OWENS, HINGLEY) carry ~£12.8M of road spend
out of 117 carriers → a procurement / negotiation lever.

**Supply Chain:** mean utilisation ~54%; a large share of loads run under 60% of
assumed capacity → consolidation opportunity (assumption-based — see §5).

> Don't memorise these — they're live. Pull them on screen with
> `queries/sample_queries.sql` (Finance Q1, anomalies Q2, reconciliation Q1).

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
   partner = to be confirmed by TSUK. Sub-carriers (117 of them) come straight from
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
FROM `prj-tsuk-looker-sa-01.searce_poc_mart.reconciliation` ORDER BY feed;
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
for p in searce_poc_stg.sp_normalise searce_poc_mart.sp_unify \
         searce_poc_mart.sp_anomalies searce_poc_mart.sp_data_quality; do
  bq query --use_legacy_sql=false --location=EU "CALL \`prj-tsuk-looker-sa-01.$p\`()"
done

# Full clean reset of a feed (e.g. re-demo from scratch): clear its raw rows then re-drop
bq query --use_legacy_sql=false --location=EU \
  'DELETE FROM `prj-tsuk-looker-sa-01.searce_poc_raw.raw_rail` WHERE TRUE'
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

## 9. Deferred until Looker access lands

- LookML model + the two persona dashboards (Finance "cost per load", Supply Chain
  "utilisation per load") + the Anomaly digest tile.
- Looker Conversational Analytics (grounded on the same marts).
- The `warm` Cloud Run service + cache-warm workflow step (commented in code,
  ready to re-enable).

Until then the BigQuery marts are fully populated and queryable — demo from
`queries/sample_queries.sql` or the BigQuery console.

---

## 10. Pre-demo checklist

- [ ] `gcloud config configurations activate tsuk-poc` (project `prj-tsuk-looker-sa-01`)
- [ ] Workflow active: `gcloud workflows describe searce-poc-pipeline --location=europe-west2 --format='value(state)'` → `ACTIVE`
- [ ] Trigger active: `gcloud eventarc triggers describe searce-poc-gcs-trigger --location=europe-west2 --format='value(name)'`
- [ ] Ingest healthy: `gcloud run services describe searce-poc-ingest --region=europe-west2 --format='value(status.url)'`
- [ ] Reconciliation clean (run §6 query → all deltas 0)
- [ ] Sample files present in `sample_data/`
- [ ] Console tabs open: Workflows executions, BigQuery (saved `sample_queries.sql`)
