# Eventarc trigger on GCS object.finalized for the landing bucket. The bucket's
# region must match var.bucket_region (GCS Eventarc triggers are region-bound).
# Runtime SA holds eventarc.eventReceiver + workflows.invoker; the GCS service
# agent holds pubsub.publisher (both granted by the admin).

resource "google_eventarc_trigger" "gcs_trigger" {
  name            = "${var.name_prefix}-gcs-trigger"
  location        = var.bucket_region
  project         = var.project_id
  service_account = local.runtime_sa_email
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
    google_project_iam_member.runtime,
    google_project_iam_member.gcs_pubsub_publisher,
    google_storage_bucket.landing,
  ]
}
