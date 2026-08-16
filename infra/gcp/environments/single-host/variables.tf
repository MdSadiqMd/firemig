variable "project_id" {
  description = "GCP project ID."
  type        = string

  validation {
    condition     = length(trimspace(var.project_id)) > 0
    error_message = "project_id must not be empty."
  }
}

variable "name_prefix" {
  description = "Prefix for environment resources."
  type        = string
  default     = "runable"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name_prefix)) && length(var.name_prefix) <= 40
    error_message = "name_prefix must be a valid lowercase GCP resource prefix with at most 40 characters."
  }
}

variable "region" {
  description = "GCP region for the single-host environment."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the runtime host."
  type        = string
  default     = "us-central1-a"

  validation {
    condition     = startswith(var.zone, "${var.region}-")
    error_message = "zone must belong to region."
  }
}

variable "subnet_cidr" {
  description = "CIDR for the custom regional subnet."
  type        = string
  default     = "10.30.0.0/24"

  validation {
    condition     = can(cidrnetmask(var.subnet_cidr))
    error_message = "subnet_cidr must be a valid CIDR."
  }
}

variable "allowed_client_cidrs" {
  description = "Client CIDRs allowed to reach the public API/proxy ports. Empty keeps those ports closed."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_client_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every allowed_client_cidrs entry must be a valid CIDR."
  }
}

variable "public_service_ports" {
  description = "TCP ports exposed only to allowed_client_cidrs."
  type        = list(number)
  default     = [443]

  validation {
    condition     = length(var.public_service_ports) > 0 && alltrue([for port in var.public_service_ports : port >= 1 && port <= 65535])
    error_message = "public_service_ports must contain valid TCP ports."
  }
}

variable "machine_type" {
  description = "Intel-supported nested virtualization machine type."
  type        = string
  default     = "n2-standard-8"
}

variable "min_cpu_platform" {
  description = "Requested Intel CPU floor. It is not proof of Firecracker snapshot compatibility."
  type        = string
  default     = "Intel Cascade Lake"
}

variable "data_disk_size_gb" {
  description = "Persistent Firecracker artifact disk size in GiB."
  type        = number
  default     = 250

  validation {
    condition     = var.data_disk_size_gb >= 100
    error_message = "data_disk_size_gb must be at least 100 GiB."
  }
}

variable "logical_worker_ids" {
  description = "Exactly two logical worker IDs advertised through instance metadata."
  type        = list(string)
  default     = ["worker-a", "worker-b"]

  validation {
    condition = (
      length(var.logical_worker_ids) == 2 &&
      length(distinct(var.logical_worker_ids)) == 2 &&
      alltrue([for id in var.logical_worker_ids : can(regex("^[a-z][a-z0-9-]{0,31}$", id))])
    )
    error_message = "logical_worker_ids must contain exactly two distinct lowercase IDs."
  }
}

variable "service_account_email" {
  description = "Optional least-privilege service account for the runtime host."
  type        = string
  default     = null
  nullable    = true
}

variable "enable_required_apis" {
  description = "Enable the Compute Engine API in the project."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Protect the runtime VM from accidental deletion."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Additional labels applied to instances and disks."
  type        = map(string)
  default     = {}
}
