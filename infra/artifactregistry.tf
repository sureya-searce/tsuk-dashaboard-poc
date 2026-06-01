resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = "${var.name_prefix}-images"
  description   = "Container images for the Searce TSUK PoC pipeline."
  format        = "DOCKER"
  labels        = var.labels

  depends_on = [google_project_service.apis]
}
