# BigQuery datasets for the domain-owned medallion. Schema/procedures are applied
# via scripts/seed-bq.sh. The dataset is the ownership/IAM boundary:
#   _raw  bronze (shared)         _stg  silver (shared conformed)
#   _core gold (shared governed)  _finance / _supplychain  gold (team-owned)
#
# When var.create_prerequisites is true (e.g. infraappsandbox, where we have Owner)
# Terraform creates the datasets and the per-team IAM. In the client project (false)
# datasets are made out-of-band and this file just exposes the names.

locals {
  bq_datasets = {
    raw         = "${var.bq_prefix}_raw"
    stg         = "${var.bq_prefix}_stg"
    core        = "${var.bq_prefix}_core"
    finance     = "${var.bq_prefix}_finance"
    supplychain = "${var.bq_prefix}_supplychain"
  }

  # owner label per dataset, for the governance/ownership story.
  dataset_owner = {
    raw         = "shared"
    stg         = "shared"
    core        = "shared"
    finance     = "finance"
    supplychain = "supplychain"
  }
}

resource "google_bigquery_dataset" "ds" {
  for_each = var.create_prerequisites ? local.bq_datasets : {}

  project       = var.project_id
  dataset_id    = each.value
  location      = "EU"
  friendly_name = "Searce PoC ${each.key} (${local.dataset_owner[each.key]})"
  labels        = merge(var.labels, { layer = each.key, owner = local.dataset_owner[each.key] })

  depends_on = [google_project_service.required]
}

# ── Per-team ownership IAM (only when team principals are supplied) ──────────
# Each team: dataEditor on its own gold dataset; dataViewer on the shared core + silver.
locals {
  finance_iam = var.create_prerequisites ? flatten([
    for m in var.finance_members : [
      { ds = local.bq_datasets.finance, role = "roles/bigquery.dataEditor", member = m },
      { ds = local.bq_datasets.core, role = "roles/bigquery.dataViewer", member = m },
      { ds = local.bq_datasets.stg, role = "roles/bigquery.dataViewer", member = m },
    ]
  ]) : []

  supplychain_iam = var.create_prerequisites ? flatten([
    for m in var.supplychain_members : [
      { ds = local.bq_datasets.supplychain, role = "roles/bigquery.dataEditor", member = m },
      { ds = local.bq_datasets.core, role = "roles/bigquery.dataViewer", member = m },
      { ds = local.bq_datasets.stg, role = "roles/bigquery.dataViewer", member = m },
    ]
  ]) : []

  team_iam = { for b in concat(local.finance_iam, local.supplychain_iam) :
  "${b.ds}|${b.role}|${b.member}" => b }
}

resource "google_bigquery_dataset_iam_member" "team" {
  for_each = local.team_iam

  project    = var.project_id
  dataset_id = each.value.ds
  role       = each.value.role
  member     = each.value.member

  depends_on = [google_bigquery_dataset.ds]
}
