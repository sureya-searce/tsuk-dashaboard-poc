resource "google_eventarc_trigger" "gcs_trigger" {
  name            = "${var.name_prefix}-gcs-trigger"
  location        = var.region
  project         = var.project_id
  service_account = google_service_account.runtime.email
  labels          = var.labels

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }

  matching_criteria {
    attribute = "bucket"
    value     = var.landing_bucket
  }

  destination {
    workflow = google_workflows_workflow.pipeline.id
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.runtime_roles,
    google_project_iam_member.gcs_pubsub_publisher,
  ]
}
