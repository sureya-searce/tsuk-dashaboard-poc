variable "project_id" {
  description = "GCP project where the PoC is deployed."
  type        = string
  default     = "prj-tsuk-looker-sa-01"
}

variable "region" {
  description = "Primary region for all regional resources."
  type        = string
  default     = "europe-west2"
}

variable "landing_bucket" {
  description = "Pre-existing GCS bucket where supplier files land. Not created by this stack."
  type        = string
  default     = "tsuk-searce-dashboard-poc"
}

variable "bucket_region" {
  description = "Region/location of the landing bucket. GCS Eventarc triggers must be created in this location (e.g. europe-west2 for regional, or 'eu' for the EU multi-region)."
  type        = string
  default     = "europe-west2"
}

variable "landing_prefix" {
  description = "Object prefix inside the landing bucket that triggers the pipeline. Files must live at landing/<supplier>/<file>.xlsx."
  type        = string
  default     = "landing/"
}

variable "suppliers" {
  description = "Allowed source subfolders under the landing prefix (landing/<source>/...). Anything outside this set is ignored by the Workflow."
  type        = set(string)
  default     = ["rail", "road_uk", "road_eu", "finance_prodcost", "finance_mgmt"]
}

variable "create_prerequisites" {
  description = "When true, Terraform provisions the full stack (APIs, runtime SA + IAM, landing bucket, Artifact Registry repo, BigQuery datasets). Set true in a project where you have Owner (e.g. infraappsandbox); leave false where APIs/SA/bucket are admin-provisioned out-of-band (the client project)."
  type        = bool
  default     = false
}

variable "finance_members" {
  description = "Principals owning the Finance gold dataset (members get dataEditor on _finance, dataViewer on _core/_stg). e.g. [\"group:finance@tatasteel.co.uk\"]. Empty = no team IAM bindings created."
  type        = list(string)
  default     = []
}

variable "supplychain_members" {
  description = "Principals owning the Supply-Chain gold dataset (dataEditor on _supplychain, dataViewer on _core/_stg). Empty = no team IAM bindings created."
  type        = list(string)
  default     = []
}

variable "name_prefix" {
  description = "Prefix applied to all created resources for cleanup and isolation."
  type        = string
  default     = "searce-poc"
}

variable "ar_repo" {
  description = "Existing Artifact Registry Docker repo to push PoC images into (we lack rights to create a new one). Reused, namespaced by image name."
  type        = string
  default     = "dashboard-summarization-docker-repo"
}

variable "bq_prefix" {
  description = "BigQuery dataset prefix (underscores only)."
  type        = string
  default     = "searce_poc"
}

variable "labels" {
  description = "Labels applied to every resource."
  type        = map(string)
  default = {
    project = "tsuk-logistics-poc"
    owner   = "searce"
    env     = "poc"
  }
}
