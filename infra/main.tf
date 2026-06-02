# APIs and the runtime service account are provisioned out-of-band by the TSUK
# platform admin (we lack serviceusage / SA-create / project-IAM-admin rights):
#   - Enabled APIs: run, eventarc, workflows, workflowexecutions, artifactregistry,
#     cloudbuild, bigquery, storage, pubsub
#   - Service account: searce-poc-runtime@<project>.iam.gserviceaccount.com,
#     with run.invoker, workflows.invoker, eventarc.eventReceiver,
#     bigquery.dataEditor, bigquery.jobUser, storage.objectViewer,
#     logging.logWriter, monitoring.metricWriter
#   - GCS service agent granted pubsub.publisher (for Eventarc GCS triggers)
#
# Terraform here manages only what our deploy-scoped roles allow us to create:
# Artifact Registry repo, Cloud Run services, the Cloud Workflow, and the
# Eventarc trigger. BigQuery datasets + schema are managed via bq + scripts/seed-bq.sh.

# The admin-provisioned runtime service account. We can act-as it but cannot
# `get` it (no iam.serviceAccounts.get), so we reference it by constructed email
# rather than a data source.
locals {
  runtime_sa_email = "searce-poc-runtime@${var.project_id}.iam.gserviceaccount.com"
  runtime_sa_id    = "projects/${var.project_id}/serviceAccounts/${local.runtime_sa_email}"
}
