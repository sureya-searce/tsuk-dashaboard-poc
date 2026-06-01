locals {
  apis = [
    "run.googleapis.com",
    "eventarc.googleapis.com",
    "workflows.googleapis.com",
    "workflowexecutions.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "looker.googleapis.com",
    "pubsub.googleapis.com",
  ]
}

# NOTE: APIs may already be enabled by TSUK at project bootstrap. We declare
# them here for completeness; if `serviceusage.services.enable` is not granted
# to the runner, comment out the `google_project_service` block and ask the
# platform team to enable any missing APIs once.
resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}
