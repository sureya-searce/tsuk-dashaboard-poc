# Runtime SA used by Cloud Run services, Workflows, and Eventarc.
# One SA across the pipeline keeps IAM simple for a PoC; we can split later if needed.
resource "google_service_account" "runtime" {
  account_id   = "${var.name_prefix}-runtime"
  display_name = "Searce TSUK PoC pipeline runtime"
  description  = "Used by Cloud Run (ingest, warm), Cloud Workflows, and Eventarc trigger."
  project      = var.project_id
}

locals {
  runtime_sa_email = google_service_account.runtime.email

  runtime_roles = [
    "roles/storage.objectViewer",       # read incoming files from landing bucket
    "roles/bigquery.dataEditor",        # write to raw_/stg_/mart_ datasets
    "roles/bigquery.jobUser",           # run load + query jobs
    "roles/run.invoker",                # workflow -> run service calls
    "roles/workflows.invoker",          # eventarc -> workflows
    "roles/eventarc.eventReceiver",     # required for eventarc-triggered flows
    "roles/logging.logWriter",          # service logs
    "roles/monitoring.metricWriter",    # cloud run autoscaling metrics
  ]
}

resource "google_project_iam_member" "runtime_roles" {
  for_each = toset(local.runtime_roles)
  project  = var.project_id
  role     = each.key
  member   = "serviceAccount:${local.runtime_sa_email}"

  depends_on = [google_service_account.runtime]
}

# Eventarc requires the GCS service agent to publish to Pub/Sub on its behalf
# when the trigger target is a Workflow. This data source pulls the GCS SA.
data "google_storage_project_service_account" "gcs_sa" {
  project = var.project_id
}

resource "google_project_iam_member" "gcs_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs_sa.email_address}"
}
