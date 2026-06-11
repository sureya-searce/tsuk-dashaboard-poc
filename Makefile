# Searce TSUK PoC — one-button Makefile.
#
# Conventions:
#   - All gcloud calls use the active configuration (`gcloud config configurations activate tsuk-poc`).
#   - Terraform manages all GCP resources except the landing bucket (pre-existing).
#   - Container images are built by Cloud Build via `gcloud run deploy --source`.

# Per-environment overrides live in local.mk (gitignored). For the infraappsandbox
# port, local.mk sets PROJECT/REGION/BUCKET/AR_REPO etc. — see local.mk.example.
-include local.mk

PROJECT     ?= prj-tsuk-looker-sa-01
REGION      ?= europe-west2
NAME_PREFIX ?= searce-poc
BQ_PREFIX   ?= searce_poc
AR_REPO     ?= dashboard-summarization-docker-repo
RUNTIME_SA  := $(NAME_PREFIX)-runtime@$(PROJECT).iam.gserviceaccount.com

INGEST_SVC  := $(NAME_PREFIX)-ingest
WARM_SVC    := $(NAME_PREFIX)-warm
WORKFLOW    := $(NAME_PREFIX)-pipeline

# Landing bucket the Eventarc trigger actually watches (confirmed against the
# live searce-poc-gcs-trigger). NOT the plain tsuk-searce-dashboard-poc bucket,
# which exists but is unwatched — dropping files there is a silent no-op.
BUCKET       ?= tsuk-searce-dashboard-poc-euw2
SAMPLE_DIR   ?= sample_data
GCLOUD_CONFIG ?= tsuk-poc

INGEST_IMG  := $(REGION)-docker.pkg.dev/$(PROJECT)/$(AR_REPO)/$(INGEST_SVC):latest
WARM_IMG    := $(REGION)-docker.pkg.dev/$(PROJECT)/$(AR_REPO)/$(WARM_SVC):latest

.PHONY: help
help:
	@echo "Targets:"
	@echo "  setup           — one-time local setup (gcloud config, ADC)"
	@echo "  bootstrap       — first-run on a fresh project: prereqs→seed→build→apply→gen-data"
	@echo "  gen-data        — regenerate the 5 synthetic workbooks into sample_data/"
	@echo "  tf-init         — terraform init"
	@echo "  tf-plan         — terraform plan"
	@echo "  tf-apply        — terraform apply (creates all GCP resources)"
	@echo "  tf-destroy      — terraform destroy"
	@echo "  seed-bq         — apply DDL + stored procedures into BigQuery"
	@echo "  truncate-bq     — empty all feed-data tables (keeps dims) for a blank→live demo"
	@echo "  delete-gcs-files— remove the supplier files from the landing bucket (clean slate)"
	@echo "  cleanup         — truncate-bq + delete-gcs-files (full blank slate for a live demo)"
	@echo "  upload-files    — upload all 5 feeds sequentially (fires the pipeline)"
	@echo "  upload-parallel — DEMO: drop all 5 feeds at once → 5 concurrent runs"
	@echo "  build-ingest    — build & push ingest image via Cloud Build"
	@echo "  build-warm      — build & push warm image via Cloud Build"
	@echo "  deploy-ingest   — deploy ingest Cloud Run (uses latest image)"
	@echo "  deploy-warm     — deploy warm Cloud Run (uses latest image)"
	@echo "  deploy-workflow — deploy/update the Cloud Workflow"
	@echo "  deploy          — build + deploy both services + workflow"
	@echo "  test            — run unit tests in services/"
	@echo "  trigger SOURCE=… FILE=…  — upload a file to landing/<source>/ (rail|road_uk|road_eu)"
	@echo "  logs-ingest     — tail ingest service logs"
	@echo "  logs-warm       — tail warm service logs"
	@echo "  exec-list       — list recent workflow executions"

# ───────────────────────────────────────────────────────────── one-time setup

.PHONY: setup
setup:
	gcloud config configurations activate $(GCLOUD_CONFIG)
	gcloud auth application-default login
	@echo "Setup complete."

# ───────────────────────────────────────────────────────────── terraform

.PHONY: tf-init tf-plan tf-apply tf-destroy
tf-init:
	cd infra && terraform init

tf-plan:
	cd infra && terraform plan

tf-apply:
	cd infra && terraform apply

tf-destroy:
	cd infra && terraform destroy

# ───────────────────────────────────────────────────────────── bigquery DDL

# Applies all SQL files in sql/ after substituting @@PROJECT@@, @@RAW@@, @@STG@@,
# @@CORE@@, @@FINANCE@@, @@SC@@ placeholders. Idempotent (CREATE OR REPLACE everywhere).
.PHONY: seed-bq
seed-bq:
	@PROJECT=$(PROJECT) BQ_PREFIX=$(BQ_PREFIX) bash scripts/seed-bq.sh

# Regenerate the five synthetic workbooks into $(SAMPLE_DIR) (deterministic).
.PHONY: gen-data
gen-data:
	python3 scripts/gen_synthetic_data.py --out-dir $(SAMPLE_DIR)

# Empties every FEED-DATA table (raw + stg.shipments + all mart) so Looker / CA
# read blank — the setup for a live "nothing exists → upload → populated" demo.
# Tables refill automatically on the next upload (Eventarc → pipeline rebuilds
# stg + mart via CREATE OR REPLACE). Deliberately does NOT touch
# stg.dim_feed / stg.dim_capacity: those are seed/reference tables that
# sp_normalise joins for mode / provider / capacity — wiping them yields null
# utilisation and broken reconciliation on rebuild. (Re-seed dims with seed-bq.)
# NB: after truncating, Clear Cache & Refresh in Looker or it serves stale cache.
TRUNCATE_TABLES := \
  $(BQ_PREFIX)_raw.raw_rail $(BQ_PREFIX)_raw.raw_road_uk $(BQ_PREFIX)_raw.raw_road_eu \
  $(BQ_PREFIX)_raw.raw_finance_prodcost $(BQ_PREFIX)_raw.raw_finance_mgmt \
  $(BQ_PREFIX)_stg.shipments $(BQ_PREFIX)_stg.production $(BQ_PREFIX)_stg.management \
  $(BQ_PREFIX)_core.movements $(BQ_PREFIX)_core.production_cost $(BQ_PREFIX)_core.cost_per_tonne \
  $(BQ_PREFIX)_core.reconciliation $(BQ_PREFIX)_core.dq_flags $(BQ_PREFIX)_core.assumptions \
  $(BQ_PREFIX)_finance.cost_analysis $(BQ_PREFIX)_finance.management_report \
  $(BQ_PREFIX)_supplychain.utilisation $(BQ_PREFIX)_supplychain.lane_performance \
  $(BQ_PREFIX)_supplychain.carrier_spend $(BQ_PREFIX)_supplychain.anomalies

.PHONY: truncate-bq
truncate-bq:
	@echo "Truncating feed-data tables (keeping dim_feed + dim_capacity)…"
	@for t in $(TRUNCATE_TABLES); do \
	  echo "  TRUNCATE $$t"; \
	  bq query --use_legacy_sql=false --location=EU --quiet \
	    "TRUNCATE TABLE \`$(PROJECT).$$t\`" >/dev/null || exit 1; \
	done
	@echo "Done — mart is empty. In Looker: Clear Cache & Refresh to show blank, then upload to rebuild."

# Deletes the supplier files currently in the landing bucket — pairs with
# truncate-bq for a true clean slate before a live upload. Safe to run anytime:
# object.finalized is the only Eventarc event, so DELETES never re-fire the
# pipeline. Idempotent — a no-op if landing is already empty.
.PHONY: delete-gcs-files
delete-gcs-files:
	@echo "Deleting landing files in gs://$(BUCKET)/landing/ …"
	@gcloud storage rm --recursive "gs://$(BUCKET)/landing/**" 2>/dev/null \
	  && echo "Deleted." \
	  || echo "Nothing to delete (landing already empty)."

# Full blank slate for a live "nothing exists → upload → populated" demo:
# empty BigQuery first, then clear the landing files. BQ-first so a stray
# in-flight pipeline run can't repopulate mart from files we're about to remove.
# After this: Clear Cache & Refresh in Looker to show the blank state.
.PHONY: cleanup
cleanup: truncate-bq delete-gcs-files
	@echo "Clean slate ready. Looker: Clear Cache & Refresh, then upload to go live."

# ───────────────────────────────────────────────────────────── services

.PHONY: build-ingest build-warm deploy-ingest deploy-warm deploy-workflow deploy
build-ingest:
	gcloud builds submit services/ingest \
	  --tag $(INGEST_IMG) \
	  --region $(REGION)

build-warm:
	gcloud builds submit services/warm \
	  --tag $(WARM_IMG) \
	  --region $(REGION)

# NB: ingress is Terraform-managed (INGRESS_TRAFFIC_ALL + no-unauthenticated in
# infra/cloudrun.tf) — don't set --ingress here or the two will drift.
deploy-ingest: build-ingest
	gcloud run deploy $(INGEST_SVC) \
	  --image $(INGEST_IMG) \
	  --region $(REGION) \
	  --service-account $(RUNTIME_SA) \
	  --no-allow-unauthenticated \
	  --update-env-vars BQ_PROJECT=$(PROJECT),BQ_RAW_DATASET=$(BQ_PREFIX)_raw,BQ_LOCATION=EU

deploy-warm: build-warm
	gcloud run deploy $(WARM_SVC) \
	  --image $(WARM_IMG) \
	  --region $(REGION) \
	  --service-account $(RUNTIME_SA) \
	  --ingress internal \
	  --no-allow-unauthenticated

deploy-workflow:
	cd infra && terraform apply -target=google_workflows_workflow.pipeline

# warm (Looker cache) deferred until Looker access lands — not in default deploy.
deploy: deploy-ingest deploy-workflow

# First-run on a fresh project (create_prerequisites=true). Sequences the
# chicken-and-egg correctly: provision the AR repo/SA/datasets/bucket FIRST, seed
# BigQuery, build+push the image, THEN apply Cloud Run/Workflow/Eventarc (which
# need the image + SA to exist), and finally generate the synthetic data.
.PHONY: bootstrap
bootstrap:
	@echo "1/5 provisioning prerequisites (APIs, SA, AR repo, bucket, datasets)…"
	cd infra && terraform init -input=false && terraform apply -input=false -auto-approve \
	  -target=google_project_service.required \
	  -target=google_service_account.runtime \
	  -target=google_project_iam_member.runtime \
	  -target=google_project_iam_member.gcs_pubsub_publisher \
	  -target=google_artifact_registry_repository.images \
	  -target=google_storage_bucket.landing \
	  -target=google_bigquery_dataset.ds
	@echo "2/5 seeding BigQuery schema + procedures…"
	@$(MAKE) seed-bq
	@echo "3/5 building + pushing the ingest image…"
	@$(MAKE) build-ingest
	@echo "4/5 applying the rest (Cloud Run, Workflow, Eventarc)…"
	cd infra && terraform apply -input=false -auto-approve
	@echo "5/5 generating synthetic data…"
	@$(MAKE) gen-data
	@echo "Bootstrap complete. Go live with: make upload-files"

# ───────────────────────────────────────────────────────────── tests

.PHONY: test
test:
	cd services/ingest && python -m pytest -q

# ───────────────────────────────────────────────────────────── ops

# Usage: make trigger SOURCE=rail FILE="sample_data/Raw Rail Data.xlsx"
.PHONY: trigger
trigger:
	@test -n "$(FILE)" || (echo "FILE=... required" && exit 1)
	@test -n "$(SOURCE)" || (echo "SOURCE=rail|road_uk|road_eu required" && exit 1)
	gcloud storage cp "$(FILE)" gs://$(BUCKET)/landing/$(SOURCE)/

# Uploads all three supplier files to their feed folders in one shot — the
# "go live" step. Each upload is its own object.finalized event, so the pipeline
# runs three independent executions (watch with `make exec-list`). Source files
# live in $(SAMPLE_DIR)/ (gitignored — real client data). Pre-flights that every
# file is non-empty and fails fast, so empty placeholders can't reach the bucket.
.PHONY: upload-files
upload-files:
	@for pair in \
	  "Raw Rail Data.xlsx:rail" \
	  "Raw Road Data Set 1.xlsx:road_uk" \
	  "Raw Road Data Set 2 .xlsx:road_eu" \
	  "Production Cost Data.xlsx:finance_prodcost" \
	  "Management Report.xlsx:finance_mgmt" ; do \
	  f="$${pair%:*}"; feed="$${pair##*:}"; \
	  test -s "$(SAMPLE_DIR)/$$f" || { echo "ERROR: $(SAMPLE_DIR)/$$f is empty or missing — aborting"; exit 1; }; \
	  echo "Uploading $$f → landing/$$feed/"; \
	  gcloud storage cp "$(SAMPLE_DIR)/$$f" "gs://$(BUCKET)/landing/$$feed/"; \
	done
	@echo "All 5 files uploaded — watch the runs with: make exec-list"

# DEMO drop — uploads all 5 feeds SIMULTANEOUSLY (backgrounded), so they land at
# the same instant → 5 concurrent object.finalized events → 5 concurrent Workflow
# executions. This is the "what if they all arrive at once?" robustness beat.
.PHONY: upload-parallel
upload-parallel:
	@echo "Dropping all 5 feeds simultaneously…"
	@for pair in \
	  "Raw Rail Data.xlsx:rail" \
	  "Raw Road Data Set 1.xlsx:road_uk" \
	  "Raw Road Data Set 2 .xlsx:road_eu" \
	  "Production Cost Data.xlsx:finance_prodcost" \
	  "Management Report.xlsx:finance_mgmt" ; do \
	  f="$${pair%:*}"; feed="$${pair##*:}"; \
	  test -s "$(SAMPLE_DIR)/$$f" || { echo "ERROR: $(SAMPLE_DIR)/$$f is empty or missing — aborting"; exit 1; }; \
	  ( gcloud storage cp "$(SAMPLE_DIR)/$$f" "gs://$(BUCKET)/landing/$$feed/" ) & \
	done; \
	wait
	@echo "All 5 landed together — watch 5 concurrent runs: make exec-list"

.PHONY: logs-ingest logs-warm exec-list
logs-ingest:
	gcloud run services logs read $(INGEST_SVC) --region $(REGION) --limit 50

logs-warm:
	gcloud run services logs read $(WARM_SVC) --region $(REGION) --limit 50

exec-list:
	gcloud workflows executions list $(WORKFLOW) --location $(REGION) --limit 10
