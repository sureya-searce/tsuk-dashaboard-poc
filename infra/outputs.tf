output "runtime_service_account" {
  description = "Runtime SA used by Cloud Run, Workflows, and Eventarc."
  value       = local.runtime_sa_email
}

output "artifact_registry_repo" {
  description = "Artifact Registry repo for container images (reused existing)."
  value       = var.ar_repo
}

output "image_ingest" {
  description = "Container image reference for the ingest service."
  value       = local.image_ingest
}

output "ingest_url" {
  description = "URL of the ingest Cloud Run service."
  value       = google_cloud_run_v2_service.ingest.uri
}

# Deferred until Looker access lands:
# output "image_warm" { value = local.image_warm }
# output "warm_url"   { value = google_cloud_run_v2_service.warm.uri }

output "workflow_name" {
  description = "Cloud Workflow name."
  value       = google_workflows_workflow.pipeline.name
}

output "eventarc_trigger_name" {
  description = "Eventarc trigger name."
  value       = google_eventarc_trigger.gcs_trigger.name
}

output "bq_datasets" {
  description = "BigQuery datasets used by the PoC."
  value       = local.bq_datasets
}
