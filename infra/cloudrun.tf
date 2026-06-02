# Cloud Run services. Images are built and pushed by `make build-*` (Cloud
# Build) into the Artifact Registry repo before the Cloud Run apply. Terraform
# manages the service resources; image tag updates via `gcloud run deploy` won't
# cause drift (ignore_changes on image).
#
# Auth: ingress = ALL but unauthenticated access is NOT granted, so callers must
# present a valid OIDC token. The Workflow calls these services as the runtime
# SA, which holds project-level roles/run.invoker (granted by the admin).

locals {
  image_ingest = "${var.region}-docker.pkg.dev/${var.project_id}/${var.ar_repo}/${var.name_prefix}-ingest:latest"
  image_warm   = "${var.region}-docker.pkg.dev/${var.project_id}/${var.ar_repo}/${var.name_prefix}-warm:latest"
}

resource "google_cloud_run_v2_service" "ingest" {
  name                = "${var.name_prefix}-ingest"
  location            = var.region
  project             = var.project_id
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false
  labels              = var.labels

  template {
    service_account                  = local.runtime_sa_email
    timeout                          = "540s"
    max_instance_request_concurrency = 1

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = local.image_ingest

      resources {
        # road_uk is ~124k rows / 20MB; openpyxl + in-memory JSON needs headroom.
        limits = {
          cpu    = "2"
          memory = "4Gi"
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

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

/* ── warm service DEFERRED until Looker access lands ───────────────────────
   Re-enable this resource (and warm_url in infra/workflows.tf, the warm_cache
   step in workflows/pipeline.yaml, and the warm outputs) once Looker is reachable.

resource "google_cloud_run_v2_service" "warm" {
  name                = "${var.name_prefix}-warm"
  location            = var.region
  project             = var.project_id
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false
  labels              = var.labels

  template {
    service_account                  = local.runtime_sa_email
    timeout                          = "120s"
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

      # Looker creds are injected once Looker access lands; until then the warm
      # service no-ops gracefully (returns SKIPPED) and the pipeline still
      # updates BigQuery end-to-end.
      env {
        name  = "LOOKER_INSTANCE_URL"
        value = "https://lookerservice.gcp.tsuk.com"
      }
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
}
─────────────────────────────────────────────────────────────────────────── */
