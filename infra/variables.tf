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

variable "landing_prefix" {
  description = "Object prefix inside the landing bucket that triggers the pipeline. Files must live at landing/<supplier>/<file>.xlsx."
  type        = string
  default     = "landing/"
}

variable "suppliers" {
  description = "Allowed source subfolders under the landing prefix (landing/<source>/...). Anything outside this set is ignored by the Workflow."
  type        = set(string)
  default     = ["rail", "road_uk", "road_eu"]
}

variable "name_prefix" {
  description = "Prefix applied to all created resources for cleanup and isolation."
  type        = string
  default     = "searce-poc"
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
