# TSUK Logistics Cost Analytics — PoC

Event-driven logistics cost analytics on Google Cloud. A logistics Excel file
dropped into a GCS landing bucket triggers a fully-automated pipeline that lands
data in BigQuery, runs SQL transformations, computes anomalies, reconciles to
source, and warms a set of Looker dashboards.

Unifies **five differently-shaped feeds** — three logistics (`rail` DB Cargo,
`road_uk` domestic, `road_eu` cross-border imports) and two finance
(`finance_prodcost` production cost, `finance_mgmt` management report) — into a
**domain-owned medallion**: a shared conformed core with team-owned Finance and
Supply-Chain gold marts on top.

The demo's spine is a **governed cross-team KPI**: "cost per tonne" means
*production cost* to Finance (~£500/t) and *transport cost* to Supply Chain
(~£7–50/t). Both correct, from one source of truth — defined once in the Looker
semantic layer (`core.cost_per_tonne`: finance | transport | **landed**) and
inherited by every dashboard and by Conversational Analytics.

**Read `docs/narrative.md` first** — it is the spine of the demo. `docs/kpi-logic.md`
documents every formula and assumption. The platform is **evidence-based by
design**: Conversational Analytics never invents numbers (it queries the LookML
semantic layer → BigQuery), every metric is a defined measure, and
`mart.reconciliation` proves totals tie back to the source files.

## Architecture

```
  landing/<feed>/*.xlsx     feed ∈ {rail, road_uk, road_eu, finance_prodcost, finance_mgmt}
  ────────────────────►  gs://<landing bucket>
                              │ object.finalized
                              ▼  Eventarc ──► Cloud Workflows (pipeline.yaml)
                              │
        ingest (Cloud Run, Excel→JSON) ──► raw_<feed>  (BRONZE, shared)
                              │
        sp_normalise · sp_finance_stage ──► stg.*      (SILVER, shared conformed)
                              │
        sp_build_core ──────────────────► core.*       (GOLD, shared governed:
                              │             movements · production_cost ·
                              │             cost_per_tonne · data_catalog)
        sp_build_finance ───────────────► finance.*    (GOLD, Finance-owned)
        sp_build_supplychain ───────────► supplychain.* (GOLD, SC-owned)
                              │
        sp_data_quality ────────────────► core.reconciliation (the £0 receipts)
                              ▼
        Looker: core / finance / supplychain models + Conversational Analytics
```

All transformation logic lives in SQL (`sql/`), not in the services. Ingest is a
dumb, unbreakable Excel→JSON loader; the SQL layer owns every business rule.

## Project layout

```
analytics_dashboard_tsuk/
├── docs/
│   ├── narrative.md         # THE demo spine — read first
│   ├── workshop-runbook.md  # live demo choreography (drop → pipeline → layers → Looker)
│   ├── demo-runbook.md      # operational companion (assumptions, failure modes, recovery)
│   └── kpi-logic.md         # every formula, source column, assumption
├── infra/                   # Terraform — all GCP resources (except the landing bucket, which exists)
├── services/
│   ├── ingest/              # Cloud Run — Excel → JSON → raw_ingest (no business logic)
│   └── warm/                # Cloud Run — calls Looker API to prime dashboard caches
├── workflows/
│   └── pipeline.yaml        # Cloud Workflow: ingest → normalise → unify → anomalies → dq → warm
├── sql/                     # BigQuery DDL + all transformation/KPI/reconciliation SQL
│   ├── 00_raw.sql           #   bronze — one JSON landing table per feed
│   ├── 05_dim_feed.sql      #   conformed dim: feed → mode/provider
│   ├── 06_dim_conformed.sql #   conformed dims: commodity, site, calendar
│   ├── 10_dim_capacity.sql  #   capacity assumptions (utilisation input)
│   ├── 20_stg_shipments.sql #   silver — sp_normalise (3 logistics feeds → movement grain)
│   ├── 25_stg_finance.sql   #   silver — sp_finance_stage (production + management)
│   ├── 30_core.sql          #   gold/core — facts + GOVERNED cost_per_tonne + data_catalog
│   ├── 40_supplychain.sql   #   gold/supplychain — utilisation, lane, carrier, anomalies
│   ├── 45_finance.sql       #   gold/finance — cost_analysis, management_report
│   └── 50_core_dq.sql       #   core — reconciliation + DQ + assumptions
├── sample_data/             # the three real sample workbooks
├── lookml/                  # LookML project (placeholder)
├── scripts/                 # Local dev helpers
└── Makefile                 # One-button deploy / destroy / test
```

## Naming conventions

| Resource | Name |
|---|---|
| GCP project | `infraappsandbox` (was `prj-tsuk-looker-sa-01`) |
| Region | `europe-west2` / BQ `EU` |
| Landing bucket | `infraappsandbox-tsuk-logistics-poc-euw2` |
| Sources (landing subfolders) | `rail`, `road_uk`, `road_eu`, `finance_prodcost`, `finance_mgmt` |
| BigQuery datasets | `searce_poc_raw`, `_stg`, `_core`, `_finance`, `_supplychain` |
| Artifact Registry repo | `searce-poc-images` |
| Cloud Run services | `searce-poc-ingest`, `searce-poc-warm` |
| Cloud Workflow | `searce-poc-pipeline` |
| Eventarc trigger | `searce-poc-gcs-trigger` |
| Runtime service account | `searce-poc-runtime@infraappsandbox.iam.gserviceaccount.com` |

Environment-specific values live in `local.mk` (Makefile) and `infra/terraform.tfvars`
(both gitignored; see the `.example` files). The in-repo defaults still point at the
original client project.

## Prerequisites

- `gcloud` configured against the `tsuk-poc` configuration (account: TSUK email, project: `prj-tsuk-looker-sa-01`, region: `europe-west2`).
- `gcloud auth application-default login` for SDK clients.
- Terraform ≥ 1.6 OR OpenTofu ≥ 1.6.
- Python ≥ 3.12.

## Setup

```bash
# One-time: point at your project (copy the example configs first)
cp local.mk.example local.mk                       # Makefile overrides
cp infra/terraform.tfvars.example infra/terraform.tfvars
make setup                                          # gcloud config + ADC login

# Fresh project (Owner): one-shot bootstrap — provisions prerequisites, seeds
# BigQuery, builds the image, applies Cloud Run/Workflow/Eventarc, generates data.
make bootstrap

# Go live
make upload-files
```

`make bootstrap` is for a project where you have Owner (`create_prerequisites=true`,
e.g. `infraappsandbox`). For the original deploy-scoped client project, use the
piecemeal `make tf-apply` → `make seed-bq` → `make deploy` flow instead.

## Trigger the pipeline

Drop a file into the landing zone under its source subfolder:

```bash
make gen-data        # (re)generate the five synthetic workbooks → sample_data/
make upload-files    # drop all five (fires five pipeline runs)
# …or one at a time:
make trigger SOURCE=rail             FILE="sample_data/Raw Rail Data.xlsx"
make trigger SOURCE=finance_prodcost FILE="sample_data/Production Cost Data.xlsx"
```

Only `landing/<source>/*.xlsx` for a known source runs the pipeline; anything
else is acknowledged and skipped. Eventarc → Workflow → ingest → normalise →
finance-stage → build-core → build-finance → build-supplychain → data-quality.
Watch with `make exec-list`.

## Tear-down

```bash
make tf-destroy
```

Bucket contents and Looker user content are NOT touched by `tf-destroy`.

## Status

Ported to a **domain-owned medallion** on `infraappsandbox` and driven by **synthetic
data** (client data stays in the client project). Five feeds (3 logistics + 2 finance)
flow through a shared conformed core into team-owned Finance and Supply-Chain gold marts,
with a governed cross-team `cost_per_tonne` KPI. Ingest header-drift tests pass; Terraform
validates; synthetic data reconciles to source.

Run order: `make bootstrap` → `make upload-files` → deploy the three Looker models
(`core`, `finance`, `supplychain`) on the Searce-Looker→infraappsandbox connection.

Looker connection: **`sureya-tsuk-logistics`** (set in `lookml/models/searce-tsuk-poc.model.lkml`).
