resource "google_workflows_workflow" "pipeline" {
  name            = "${var.name_prefix}-pipeline"
  region          = var.region
  project         = var.project_id
  description     = "Searce TSUK PoC: ingest → SQL chain → warm. Triggered by Eventarc on GCS object.finalized."
  service_account = google_service_account.runtime.id
  labels          = var.labels

  source_contents = templatefile("${path.module}/../workflows/pipeline.yaml", {
    project_id       = var.project_id
    region           = var.region
    raw_dataset      = local.bq_datasets.raw
    stg_dataset      = local.bq_datasets.stg
    mart_dataset     = local.bq_datasets.mart
    ingest_url       = google_cloud_run_v2_service.ingest.uri
    warm_url         = google_cloud_run_v2_service.warm.uri
    landing_prefix   = var.landing_prefix
    allowed_feeds    = jsonencode([for s in var.suppliers : s])
  })

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.runtime_roles,
  ]
}
