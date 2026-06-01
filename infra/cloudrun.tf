# Cloud Run services. Images are built and pushed out-of-band by `make deploy`
# (Cloud Build via `gcloud run deploy --source`). Terraform manages the service
# resource itself; image tags can be updated via `terraform apply` or directly
# via gcloud — both write to the same Cloud Run service object.

locals {
  image_ingest = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}/ingest:latest"
  image_warm   = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}/warm:latest"
}

resource "google_cloud_run_v2_service" "ingest" {
  name                = "${var.name_prefix}-ingest"
  location            = var.region
  project             = var.project_id
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = false
  labels              = var.labels

  template {
    service_account = google_service_account.runtime.email
    timeout         = "540s"
    max_instance_request_concurrency = 1

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = local.image_ingest

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      env {
        name  = "BQ_PROJECT"
        value = var.project_id
      }
      env {
        name  = "BQ_RAW_DATASET"
        value = local.bq_datasets.raw
      }
      env {
        name  = "BQ_LOCATION"
        value = "EU"
      }
    }
  }

  # Allow image updates from `gcloud run deploy` without TF drift screaming.
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.runtime_roles,
  ]
}

resource "google_cloud_run_v2_service" "warm" {
  name                = "${var.name_prefix}-warm"
  location            = var.region
  project             = var.project_id
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = false
  labels              = var.labels

  template {
    service_account = google_service_account.runtime.email
    timeout         = "120s"
    max_instance_request_concurrency = 1

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = local.image_warm

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      env {
        name  = "LOOKER_INSTANCE_URL"
        value = "https://lookerservice.gcp.tsuk.com"
      }
      # Looker API client id/secret should be set out-of-band (Secret Manager
      # or env override) once Looker user provisioning is done. Left as
      # placeholders here to keep the deploy plan working.
      env {
        name  = "LOOKER_CLIENT_ID"
        value = ""
      }
      env {
        name  = "LOOKER_CLIENT_SECRET"
        value = ""
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].containers[0].env,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.runtime_roles,
  ]
}

# Allow the runtime SA (used by Workflows) to invoke both Cloud Run services.
resource "google_cloud_run_v2_service_iam_member" "ingest_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.ingest.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_cloud_run_v2_service_iam_member" "warm_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.warm.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.runtime.email}"
}
