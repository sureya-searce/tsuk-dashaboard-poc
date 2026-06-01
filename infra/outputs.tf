output "runtime_service_account" {
  description = "Runtime SA used by Cloud Run, Workflows, and Eventarc."
  value       = google_service_account.runtime.email
}

output "artifact_registry_repo" {
  description = "Artifact Registry repo for container images."
  value       = google_artifact_registry_repository.images.name
}

output "image_ingest" {
  description = "Container image reference for the ingest service."
  value       = local.image_ingest
}

output "image_warm" {
  description = "Container image reference for the warm service."
  value       = local.image_warm
}

output "ingest_url" {
  description = "Internal URL of the ingest Cloud Run service."
  value       = google_cloud_run_v2_service.ingest.uri
}

output "warm_url" {
  description = "Internal URL of the warm Cloud Run service."
  value       = google_cloud_run_v2_service.warm.uri
}

output "workflow_name" {
  description = "Cloud Workflow name."
  value       = google_workflows_workflow.pipeline.name
}

output "eventarc_trigger_name" {
  description = "Eventarc trigger name."
  value       = google_eventarc_trigger.gcs_trigger.name
}

output "bq_datasets" {
  description = "BigQuery datasets created for the PoC."
  value       = local.bq_datasets
}
