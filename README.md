# TSUK Logistics Cost Analytics — PoC

Event-driven logistics cost analytics on Google Cloud. A logistics Excel file
dropped into a GCS landing bucket triggers a fully-automated pipeline that lands
data in BigQuery, runs SQL transformations, computes anomalies, reconciles to
source, and warms a set of Looker dashboards.

Unifies **three differently-shaped feeds** — `rail` (DB Cargo), `road_uk`
(domestic), `road_eu` (cross-border imports) — into one canonical model so
Finance ("cost per load") and Supply Chain ("utilisation per load") can ask one
question across all three.

**Read `docs/narrative.md` first** — it is the spine of the demo. `docs/kpi-logic.md`
documents every formula and assumption. The platform is **evidence-based by
design**: Conversational Analytics never invents numbers (it queries the LookML
semantic layer → BigQuery), every metric is a defined measure, and
`mart.reconciliation` proves totals tie back to the source files.

## Architecture

```
  landing/<source>/*.xlsx          source ∈ {rail, road_uk, road_eu}
  ────────────────────►  gs://tsuk-searce-dashboard-poc
                                  │ object.finalized
                                  ▼  Eventarc  ──►  Cloud Workflows (pipeline.yaml)
                                  │
   ┌──────────────┬──────────────┼───────────────┬───────────────┐
   ▼              ▼              ▼               ▼               ▼
 ingest      sp_normalise     sp_unify      sp_anomalies   sp_data_quality   warm
 (Cloud Run) raw→canonical   →mart fact    →Top-10 digest  →reconciliation  (Looker)
 Excel→JSON   (stg.shipments) (mart.*)      (mart.anomalies)(mart.recon...)  cache
   │
   ▼
 raw_ingest (JSON, lineage)
```

All transformation logic lives in SQL (`sql/`), not in the services. Ingest is a
dumb, unbreakable Excel→JSON loader; the SQL layer owns every business rule.

## Project layout

```
analytics_dashboard_tsuk/
├── docs/
│   ├── narrative.md         # THE demo spine — read first
│   └── kpi-logic.md         # every formula, source column, assumption
├── infra/                   # Terraform — all GCP resources (except the landing bucket, which exists)
├── services/
│   ├── ingest/              # Cloud Run — Excel → JSON → raw_ingest (no business logic)
│   └── warm/                # Cloud Run — calls Looker API to prime dashboard caches
├── workflows/
│   └── pipeline.yaml        # Cloud Workflow: ingest → normalise → unify → anomalies → dq → warm
├── sql/                     # BigQuery DDL + all transformation/KPI/anomaly/reconciliation SQL
│   ├── 00_raw.sql           #   raw_ingest (JSON landing)
│   ├── 10_dim_capacity.sql  #   capacity assumptions (utilisation input)
│   ├── 20_stg_shipments.sql #   sp_normalise — 3 feeds → canonical movement grain
│   ├── 30_mart_core.sql     #   sp_unify — fact + lane/kpi rollups
│   ├── 40_mart_anomalies.sql#   sp_anomalies — rule-based Top-10
│   └── 50_dq_reconciliation.sql # sp_data_quality — reconcile to source + DQ flags
├── sample_data/             # the three real sample workbooks
├── lookml/                  # LookML project (placeholder)
├── scripts/                 # Local dev helpers
└── Makefile                 # One-button deploy / destroy / test
```

## Naming conventions

| Resource | Name |
|---|---|
| GCP project | `prj-tsuk-looker-sa-01` |
| Region | `europe-west2` |
| Landing bucket (exists) | `tsuk-searce-dashboard-poc` |
| Sources (landing subfolders) | `rail`, `road_uk`, `road_eu` |
| BigQuery datasets | `searce_poc_raw`, `searce_poc_stg`, `searce_poc_mart` |
| Artifact Registry repo | `searce-poc-images` |
| Cloud Run services | `searce-poc-ingest`, `searce-poc-warm` |
| Cloud Workflow | `searce-poc-pipeline` |
| Eventarc trigger | `searce-poc-gcs-trigger` |
| Runtime service account | `searce-poc-runtime@prj-tsuk-looker-sa-01.iam.gserviceaccount.com` |

## Prerequisites

- `gcloud` configured against the `tsuk-poc` configuration (account: TSUK email, project: `prj-tsuk-looker-sa-01`, region: `europe-west2`).
- `gcloud auth application-default login` for SDK clients.
- Terraform ≥ 1.6 OR OpenTofu ≥ 1.6.
- Python ≥ 3.12.

## Setup

```bash
# One-time
make tf-init
make adc-login

# Provision everything (Terraform)
make tf-plan
make tf-apply

# Deploy services
make deploy

# Deploy workflow
make deploy-workflow
```

## Trigger the pipeline

Drop a file into the landing zone under its source subfolder:

```bash
make trigger SOURCE=rail    FILE="sample_data/Raw Rail Data.xlsx"
make trigger SOURCE=road_uk FILE="sample_data/Raw Road Data Set 1.xlsx"
make trigger SOURCE=road_eu FILE="sample_data/Raw Road Data Set 2 .xlsx"
```

Only `landing/<source>/*.xlsx` for a known source runs the pipeline; anything
else is acknowledged and skipped. Eventarc → Workflow → ingest → normalise →
unify → anomalies → data-quality → warm. Watch with `make exec-list`.

## Tear-down

```bash
make tf-destroy
```

Bucket contents and Looker user content are NOT touched by `tf-destroy`.

## Status

Built locally — not yet deployed. Transformation logic validated against the
real sample files: the canonical model reconciles to source control totals to
the penny (rail £27.12M, road_uk £36.37M, road_eu £17.93M).

Pending:
- Looker user provisioning (`sureya.sathiamoorthi@tatasteel.co.uk` on `looker-instance-p-01`).
- LookML model + dashboards (authored in Looker once access lands).
- First live deploy (`make tf-apply` → `make seed-bq` → `make deploy`).
