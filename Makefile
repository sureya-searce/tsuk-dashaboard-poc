# Searce TSUK PoC — one-button Makefile.
#
# Conventions:
#   - All gcloud calls use the active configuration (`gcloud config configurations activate tsuk-poc`).
#   - Terraform manages all GCP resources except the landing bucket (pre-existing).
#   - Container images are built by Cloud Build via `gcloud run deploy --source`.

PROJECT     := prj-tsuk-looker-sa-01
REGION      := europe-west2
NAME_PREFIX := searce-poc
BQ_PREFIX   := searce_poc
AR_REPO     := $(NAME_PREFIX)-images
RUNTIME_SA  := $(NAME_PREFIX)-runtime@$(PROJECT).iam.gserviceaccount.com

INGEST_SVC  := $(NAME_PREFIX)-ingest
WARM_SVC    := $(NAME_PREFIX)-warm
WORKFLOW    := $(NAME_PREFIX)-pipeline

INGEST_IMG  := $(REGION)-docker.pkg.dev/$(PROJECT)/$(AR_REPO)/ingest:latest
WARM_IMG    := $(REGION)-docker.pkg.dev/$(PROJECT)/$(AR_REPO)/warm:latest

.PHONY: help
help:
	@echo "Targets:"
	@echo "  setup           — one-time local setup (gcloud config, ADC)"
	@echo "  tf-init         — terraform init"
	@echo "  tf-plan         — terraform plan"
	@echo "  tf-apply        — terraform apply (creates all GCP resources)"
	@echo "  tf-destroy      — terraform destroy"
	@echo "  seed-bq         — apply DDL + stored procedures into BigQuery"
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
	gcloud config configurations activate tsuk-poc
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

# Applies all SQL files in sql/ after substituting @@PROJECT@@, @@RAW@@,
# @@STG@@, @@MART@@ placeholders. Idempotent (CREATE OR REPLACE everywhere).
.PHONY: seed-bq
seed-bq:
	@bash scripts/seed-bq.sh

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

deploy-ingest: build-ingest
	gcloud run deploy $(INGEST_SVC) \
	  --image $(INGEST_IMG) \
	  --region $(REGION) \
	  --service-account $(RUNTIME_SA) \
	  --ingress internal \
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

deploy: deploy-ingest deploy-warm deploy-workflow

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
	gcloud storage cp "$(FILE)" gs://tsuk-searce-dashboard-poc/landing/$(SOURCE)/

.PHONY: logs-ingest logs-warm exec-list
logs-ingest:
	gcloud run services logs read $(INGEST_SVC) --region $(REGION) --limit 50

logs-warm:
	gcloud run services logs read $(WARM_SVC) --region $(REGION) --limit 50

exec-list:
	gcloud workflows executions list $(WORKFLOW) --location $(REGION) --limit 10
