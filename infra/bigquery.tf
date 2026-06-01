locals {
  bq_datasets = {
    raw  = "${var.bq_prefix}_raw"
    stg  = "${var.bq_prefix}_stg"
    mart = "${var.bq_prefix}_mart"
  }
}

resource "google_bigquery_dataset" "datasets" {
  for_each = local.bq_datasets

  dataset_id  = each.value
  project     = var.project_id
  location    = "EU"
  description = "Searce TSUK PoC — ${each.key} layer"
  labels      = var.labels

  # PoC: explicit table-level cleanup, no default expiry to avoid surprises.
  default_table_expiration_ms = null

  access {
    role          = "OWNER"
    user_by_email = google_service_account.runtime.email
  }

  # Required by BigQuery — keep project-level owners.
  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }
  access {
    role          = "READER"
    special_group = "projectReaders"
  }
  access {
    role          = "WRITER"
    special_group = "projectWriters"
  }
}
