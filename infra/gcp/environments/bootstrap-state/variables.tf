variable "project_id" {
  description = "GCP project ID that owns the Terraform state bucket."
  type        = string

  validation {
    condition     = length(trimspace(var.project_id)) > 0
    error_message = "project_id must not be empty."
  }
}

variable "bucket_name" {
  description = "Globally unique GCS bucket name for Terraform state."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid globally unique GCS bucket name between 3 and 63 characters."
  }
}

variable "location" {
  description = "GCS bucket location or multi-region."
  type        = string
  default     = "US"
}

variable "storage_class" {
  description = "GCS storage class for Terraform state."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE", "REGIONAL", "MULTI_REGIONAL"], var.storage_class)
    error_message = "storage_class must be a supported GCS storage class."
  }
}

variable "kms_key_name" {
  description = "Optional Cloud KMS CryptoKey resource name for customer-managed encryption."
  type        = string
  default     = null
  nullable    = true
}

variable "enable_required_apis" {
  description = "Enable the Cloud Storage API in the project."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Additional labels applied to the state bucket."
  type        = map(string)
  default     = {}
}
