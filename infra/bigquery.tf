# BigQuery datasets are created via `bq mk` and their schema/procedures via
# scripts/seed-bq.sh (the runtime SA already holds project-level
# bigquery.dataEditor + jobUser, so no per-dataset ACLs are needed here).
#
# This file only exposes the dataset names as locals for Cloud Run env vars and
# the Workflow template.

locals {
  bq_datasets = {
    raw  = "${var.bq_prefix}_raw"
    stg  = "${var.bq_prefix}_stg"
    mart = "${var.bq_prefix}_mart"
  }
}
