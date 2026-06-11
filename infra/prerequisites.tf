# Prerequisites — created ONLY when var.create_prerequisites = true (a project where
# we have Owner, e.g. infraappsandbox). In the client project these are provisioned
# out-of-band by the platform admin (see infra/main.tf) and this file is inert.
#
# Covers everything the deploy-scoped stack assumes pre-exists: enabled APIs, the
# runtime service account + its project IAM, the GCS→Pub/Sub grant for Eventarc,
# the Artifact Registry repo, and the landing bucket.

locals {
  required_apis = [
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com",
    "workflows.googleapis.com",
    "workflowexecutions.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "logging.googleapis.com",
  ]

  # Project roles the runtime SA needs to run the pipeline end-to-end.
  runtime_roles = [
    "roles/run.invoker",            # Workflow → ingest (OIDC)
    "roles/workflows.invoker",      # Eventarc → Workflow
    "roles/eventarc.eventReceiver", # receive GCS events
    "roles/bigquery.dataEditor",    # build stg/core/finance/supplychain tables
    "roles/bigquery.jobUser",       # run BQ jobs
    "roles/storage.objectViewer",   # ingest reads the landing file
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]
}

resource "google_project_service" "required" {
  for_each = var.create_prerequisites ? toset(local.required_apis) : []

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Runtime service account (email must match local.runtime_sa_email in main.tf).
resource "google_service_account" "runtime" {
  count = var.create_prerequisites ? 1 : 0

  project      = var.project_id
  account_id   = "${var.name_prefix}-runtime"
  display_name = "Searce PoC runtime (Cloud Run / Workflows / Eventarc)"

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "runtime" {
  for_each = var.create_prerequisites ? toset(local.runtime_roles) : []

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${local.runtime_sa_email}"

  depends_on = [google_service_account.runtime]
}

# Eventarc GCS triggers publish via Pub/Sub as the GCS service agent.
data "google_storage_project_service_account" "gcs" {
  count   = var.create_prerequisites ? 1 : 0
  project = var.project_id

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "gcs_pubsub_publisher" {
  count = var.create_prerequisites ? 1 : 0

  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs[0].email_address}"
}

# Artifact Registry repo for the container images.
resource "google_artifact_registry_repository" "images" {
  count = var.create_prerequisites ? 1 : 0

  project       = var.project_id
  location      = var.region
  repository_id = var.ar_repo
  format        = "DOCKER"
  description   = "Searce TSUK PoC container images"
  labels        = var.labels

  depends_on = [google_project_service.required]
}

# Landing bucket the Eventarc trigger watches. force_destroy so tf-destroy is clean.
resource "google_storage_bucket" "landing" {
  count = var.create_prerequisites ? 1 : 0

  project                     = var.project_id
  name                        = var.landing_bucket
  location                    = var.bucket_region
  uniform_bucket_level_access = true
  force_destroy               = true
  labels                      = var.labels

  depends_on = [google_project_service.required]
}
