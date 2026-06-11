resource "google_workflows_workflow" "pipeline" {
  name            = "${var.name_prefix}-pipeline"
  region          = var.region
  project         = var.project_id
  description     = "Searce TSUK PoC: ingest → SQL chain → DQ → warm. Triggered by Eventarc on GCS object.finalized."
  service_account = local.runtime_sa_id
  labels          = var.labels

  source_contents = templatefile("${path.module}/../workflows/pipeline.yaml", {
    project_id      = var.project_id
    region          = var.region
    raw_dataset     = local.bq_datasets.raw
    stg_dataset     = local.bq_datasets.stg
    core_dataset    = local.bq_datasets.core
    finance_dataset = local.bq_datasets.finance
    sc_dataset      = local.bq_datasets.supplychain
    ingest_url      = google_cloud_run_v2_service.ingest.uri
    # warm_url      = google_cloud_run_v2_service.warm.uri   # deferred: Looker not yet accessible
    landing_prefix = var.landing_prefix
    allowed_feeds  = jsonencode([for s in var.suppliers : s])
  })

  depends_on = [
    google_project_service.required,
    google_service_account.runtime,
  ]
}
