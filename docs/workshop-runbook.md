# Workshop Demo Runbook — the live flow

The minute-by-minute choreography for the TSUK workshop demo: what to drop, what
to show, what to say, and what to build live. For operational depth (assumptions,
failure modes, exact numbers) see `docs/demo-runbook.md`; for the story, `docs/narrative.md`.

> One-line spine: **"Two dashboards, one word — 'cost per tonne' — different numbers.
> Both correct. The semantic layer over one governed foundation fixes it."**

---

## 0. Before the room (pre-flight)

**Tabs to open (in order you'll use them):**
1. Terminal (this repo) — for the file drop.
2. GCS bucket → `gs://infraappsandbox-tsuk-logistics-poc-euw2/landing/` (the drop zone).
3. **Cloud Workflows → `searce-poc-pipeline` → Executions** — *this is the pipeline to show.*
4. BigQuery → the five datasets (`searce_poc_raw / _stg / _core / _finance / _supplychain`),
   with `queries/sample_queries.sql` pasted into a query tab.
5. Looker — the two persona dashboards + the governance tile (pre-built, see §6), plus
   the **"Cost per Tonne (governed)"** Explore in the `searce-tsuk-poc` model (for the live build).

**Pre-build in Looker (do this beforehand — see §6 for tile specs):**
- Finance dashboard ("Richard Williams — Finance")
- Supply Chain dashboard ("Dan Jones — Supply Chain")
- One **KPI Governance** tile (cost-per-tonne, three bases)

**Blank the slate so the demo goes empty → live:**
```bash
make cleanup            # truncates BigQuery + clears the landing folder
```
Then in Looker: **Clear Cache & Refresh** on the dashboards — they now show empty.

**Sanity check (private, before the room):** `make exec-list` is quiet, datasets empty.

---

## 1. The blank canvas  ·  ~30s

- Show the two Looker dashboards — **empty**. "These are the Finance and Supply Chain
  views. No data yet."
- Show the empty `landing/` folder and (optionally) an empty BigQuery dataset.
- **Say:** *"Today this is three spreadsheets, emailed monthly, six days end-to-end, one
  analyst — and a static Power BI you can look at but can't ask anything."*

## 2. The drop  ·  ~15s  ·  ONE command

```bash
make upload-parallel
```

- **Say:** *"Each feed normally arrives separately. But watch what happens if all five —
  three logistics, two finance — land at the exact same moment."*
- `upload-parallel` backgrounds all five uploads so they land together → five concurrent
  `object.finalized` events. (Use `make upload-files` if you'd rather drop them one-by-one
  for a calmer story.)

## 3. The pipeline runs itself  ·  ~1–2 min  ·  **Cloud Workflows**

- Switch to **Cloud Workflows → `searce-poc-pipeline` → Executions**. **Five executions**
  appear, running concurrently. Refresh — they go green (`Succeeded`).
- Click into one execution → show the **step graph**:
  `ingest → normalise → finance_stage → build_core → build_finance → build_supplychain → data_quality`.
- **Say:** *"No scheduler, no human. Eventarc saw the file, Cloud Run parsed it, and the SQL
  chain rebuilt the warehouse. Five files, five independent runs — and there are guardrails:
  drop into the wrong folder and it's safely skipped, not ingested."*
- CLI alternative on screen: `make exec-list`.

## 4. The three layers — explain raw / stg / gold  ·  ~2–3 min  ·  **BigQuery**

Open the five datasets in the BigQuery explorer. This is the **medallion**: raw (bronze) →
stg (silver) → gold, with gold **split by ownership**.

**`searce_poc_raw` — bronze, "a faithful copy of what arrived."**
- Open `raw_road_eu`, preview a row → show `payload_json` (the whole source row as JSON) +
  `source_file`, `row_idx`, `ingested_at`.
- **Say:** *"We change nothing here. Five feeds, 10–34 different columns each, one is billing-line
  shaped. We store every row as JSON with full lineage — so a supplier renaming a column never
  breaks the pipeline, and every number can be traced back to a file and a row."*

**`searce_poc_stg` — silver, "make different shapes into one clean shape."**
- Open `stg.shipments` → one row per movement, same columns for all three logistics feeds.
- **Say:** *"Three differently-shaped feeds, now one canonical movement. The European feed's
  ~4 billing lines per shipment were collapsed into one. This is also where the cleaning and
  typing happen — all in visible SQL, not hidden in code."*
- Show `stg.production`, `stg.management` (finance, same treatment) and `dim_commodity` /
  `dim_calendar`. *"Conformed dimensions — the shared keys every team joins on, so Finance and
  Supply Chain line up by commodity and period."*

**`searce_poc_core` — gold (shared, governed), "the answers everyone trusts."**
- `core.movements`, `core.production_cost` — the conformed facts.
- `core.reconciliation` — run sample query #0: **delta £0 on every feed.** *"The receipts:
  computed totals checked against control totals taken straight from the source columns — they
  match to the penny."*
- `core.cost_per_tonne` — the governed cross-team KPI (used in §5).
- `core.data_catalog` — *"and the platform knows who owns what: shared core vs team-owned."*

**`searce_poc_finance` / `searce_poc_supplychain` — gold (team-owned).**
- **Say:** *"Each team owns its own tables, built on top of the shared core they read but don't
  edit. In BigQuery the dataset is the access boundary — that's how 'shared vs team-owned' is
  enforced, not just named."*

## 5. The reveal — two truths from one source  ·  ~1 min

Run sample query #1 (`core.cost_per_tonne` by commodity):

| commodity | finance £/t | logistics £/t | landed £/t |
|---|---|---|---|
| Coil | ~£480 | ~£7 | ~£487 |

- **Say:** *"Ask Finance their cost per tonne — they say ~£480, the cost to make the steel. Ask
  Supply Chain — ~£7, the cost to move it. Same words, different numbers, both completely correct.
  Today that quietly erodes trust in dashboards — and tomorrow an AI agent picks one definition
  and answers confidently. The fix isn't to argue; it's to define each explicitly, once, and bless
  a governed 'landed' total — in the semantic layer everything inherits."*

## 6. Looker — persona dashboards + a live build  ·  ~3–4 min

### Setup (once, before the day)
1. The two dashboards are **LookML dashboards** in the project
   (`lookml/dashboards/finance.dashboard.lookml`, `supplychain.dashboard.lookml`) —
   they appear under the `searce-tsuk-poc` LookML project as soon as the files are in.
2. **LookML dashboards are read-only in the UI** — you cannot add a tile to them from
   an Explore. So for the live "add a widget" beat: open each dashboard →
   **⋮ More → Copy** into your demo folder. **Demo from the copies** (user-defined,
   editable); keep the LookML originals as the pristine fallback.

### Pre-built dashboards (show these)

**Finance — "Richard Williams"** (Explores under **Finance** group):
| Tile | Explore | Fields |
|---|---|---|
| Production cost / tonne | Production Cost Analysis | `commodity` × `production_cost_per_tonne_w` (column) |
| Variance to standard | Production Cost Analysis | `site`, `total_variance_gbp` (bar, sorted) |
| Working capital vs plan | Management Report | `cost_centre` × `total_amount` vs `total_plan` (filter Category = Working Capital) |
| Energy cost trend | Production Cost Analysis | `financial_period` × `total_energy_cost` (line) |

**Supply Chain — "Dan Jones"** (Explores under **Supply Chain** group):
| Tile | Explore | Fields |
|---|---|---|
| Transport cost / tonne | Lane Performance | `feed` × `transport_cost_per_tonne` |
| Utilisation | Utilisation | `equipment_type` × `avg_utilisation`; single-value `total_under_60` |
| Carrier concentration | Carrier Spend | `carrier` × `sum_cost` (bar, top 10) |
| Cost-leakage Top-10 | Cost Leakage | `rule_label`, `lane`, `carrier`, `cost_gbp`, `impact_score` (table, sort impact desc) |

**KPI Governance tile** (Explore: **Cost per Tonne (governed)**): `commodity` × `cost_per_tonne_finance`,
`cost_per_tonne_logistics`, `cost_per_tonne_landed` (grouped bar) — the §5 reveal, visual.

### Build ONE widget LIVE (the "build it in the room" beat)

> Recommended live build — it *is* the spine and proves governed self-serve.

1. Open Explore **"Cost per Tonne (governed)"** (model `searce-tsuk-poc`, Governed Core group).
2. Pick dimension **Commodity**.
3. Pick measures **Cost per Tonne — Finance basis** and **Cost per Tonne — Logistics basis**
   (add **Landed (GOVERNED)** too if you want the resolution in the same chart).
4. Run → switch visualization to **Column/Bar**.
5. **Save → To an existing dashboard → the COPIED "TSUK Finance" dashboard** (the
   user-defined copy from Setup — LookML originals won't accept new tiles).
6. Open the dashboard — the new governed-KPI widget is live next to Finance's own tiles.
   *"That chart is a BI ticket today. Thirty seconds here — and it inherits the
   signed-off definitions, because the building blocks are governed."*

Rehearse this twice before the day: the whole beat should take under 60 seconds.

- **Say:** *"This chart is a BI ticket today — days in a queue. Built in the room, drag-and-drop,
  no SQL — and because it's built from governed fields it inherits the signed-off definition. Same
  building blocks Finance and Supply Chain both pull from."*
- **Alternative live build** (mirrors the deck's Cognos beat): Management Report → `line_item` ×
  `total_amount` vs `total_plan`, filtered to Working Capital — "the working-capital report, built
  live on the semantic layer."

## 7. Talk to it — Conversational Analytics  ·  ~2 min

**Agent setup (pre-built — CA allows max 5 Explores per agent, which IS the pattern:
one agent per persona, both inheriting the governed KPI explore):**

| Agent | Explores (≤5) |
|---|---|
| **TSUK Finance Agent** (Richard) | Cost per Tonne (governed) · Production Cost Analysis · Management Report · Production Cost (conformed fact) |
| **TSUK Supply Chain Agent** (Dan) | Cost per Tonne (governed) · Logistics Movements · Carrier Spend · Utilisation · Cost Leakage (Top-N) |

(Single-agent alternative covering all 5 prompts: Cost per Tonne (governed) · Logistics
Movements · Management Report · Carrier Spend · Cost Leakage. Don't add Data Catalog —
it's governance metadata, not NL-queryable content.)

Per-agent instructions: each agent answers the unqualified "cost per tonne" with **its
own team's basis** (that's what the team means by the words), and surfaces the governed
landed definition ONLY when explicitly asked to compare / for the governed-standard view.

**The choreography — divergence first, governance as the resolution** (Show reasoning on):
1. Ask **both agents**: *"What's our cost per tonne?"*
   → Finance agent: **£499.50** (production basis) · Supply Chain agent: **£9.14**
   (transport basis). *Same question, different numbers, both correct — the problem, live.*
2. Ask either agent: *"How does that compare to the governed cost per tonne?"*
   → all three bases, clearly labelled, with **Landed (GOVERNED) = £508.64** — the
   semantic layer resolving the ambiguity on demand. (Exact numbers are stable —
   the data generator is deterministic.)
3. *"What's our working capital this period vs plan?"* (Finance agent)
4. *"Where are we paying for loads under 60% utilised?"* (Supply Chain agent)
5. *"Which carriers concentrate our road spend?"* (Supply Chain agent)

- **Say:** *"Each team's agent answers in its team's language — that's today's reality, and
  both are right. The difference is: the definitions now live in one governed semantic
  layer, so the moment you ask 'compare against the standard', every agent resolves to the
  same signed-off landed number. The ambiguity is governed, not accidental."*

## 8. The close  ·  ~30s

- **Say:** *"Three spreadsheets, a week and a person — now one file drop, one governed foundation,
  and every team plus the AI inheriting the same definitions. The architecture you saw — record →
  intelligence → insight, shared core with team-owned marts — is the target picture. This is the
  control panel for the costs you can actually move."*

---

## Recovery (if something looks off mid-demo)

```bash
# Re-run the whole transform once (idempotent) — fixes any transient mid-rebuild view
for p in searce_poc_stg.sp_normalise searce_poc_stg.sp_finance_stage \
         searce_poc_core.sp_build_core searce_poc_finance.sp_build_finance \
         searce_poc_supplychain.sp_build_supplychain searce_poc_core.sp_data_quality; do
  bq query --use_legacy_sql=false --location=EU "CALL \`infraappsandbox.$p\`()"; done

# Full reset to re-run the whole demo from blank:
make cleanup            # then Clear Cache & Refresh in Looker, then `make upload-parallel`
```

## Quick reference

| Beat | Command / screen |
|---|---|
| Blank the slate | `make cleanup` + Looker Clear Cache & Refresh |
| Drop all 5 at once | `make upload-parallel` |
| Drop one-by-one | `make upload-files` (or `make trigger SOURCE=… FILE=…`) |
| The pipeline to show | Cloud Workflows → `searce-poc-pipeline` → Executions |
| Watch from CLI | `make exec-list` |
| The receipts | sample query #0 → `core.reconciliation` (delta £0) |
| The reveal | sample query #1 → `core.cost_per_tonne` |
