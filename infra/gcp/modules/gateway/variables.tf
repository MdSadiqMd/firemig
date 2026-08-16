variable "project_id" {
  description = "GCP project containing the gateway."
  type        = string
}

variable "name" {
  description = "Gateway instance name."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name)) && length(var.name) <= 63
    error_message = "name must be a valid GCP resource name with at most 63 characters."
  }
}

variable "zone" {
  description = "Zone in which to create the gateway."
  type        = string
}

variable "subnetwork" {
  description = "Fully qualified subnetwork ID."
  type        = string
}

variable "machine_type" {
  description = "Gateway machine type."
  type        = string
  default     = "n2-standard-8"
}

variable "min_cpu_platform" {
  description = "Minimum Intel CPU platform requested for the x86_64 gateway."
  type        = string
  default     = "Intel Cascade Lake"

  validation {
    condition     = startswith(var.min_cpu_platform, "Intel ")
    error_message = "min_cpu_platform must select an Intel x86_64 platform."
  }
}

variable "boot_disk_size_gb" {
  description = "Debian boot disk size in GiB."
  type        = number
  default     = 30

  validation {
    condition     = var.boot_disk_size_gb >= 20
    error_message = "boot_disk_size_gb must be at least 20 GiB."
  }
}

variable "app_user" {
  description = "Unprivileged application user created during startup."
  type        = string
  default     = "runable"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,30}$", var.app_user))
    error_message = "app_user must be a valid Linux user name."
  }
}

variable "app_group" {
  description = "Primary application group created during startup."
  type        = string
  default     = "runable"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,30}$", var.app_group))
    error_message = "app_group must be a valid Linux group name."
  }
}

variable "app_directories" {
  description = "Application directories created and owned by the application user."
  type        = list(string)
  default     = ["/var/lib/runable", "/etc/runable"]

  validation {
    condition     = alltrue([for path in var.app_directories : can(regex("^/[A-Za-z0-9._/-]+$", path))])
    error_message = "app_directories entries must be absolute paths without whitespace."
  }
}

variable "network_tags" {
  description = "Network tags used by firewall rules."
  type        = list(string)
  default     = []
}

variable "metadata" {
  description = "Application metadata merged with mandatory OS Login metadata."
  type        = map(string)
  default     = {}
}

variable "service_account_email" {
  description = "Service account email. Null uses the project's default Compute Engine service account."
  type        = string
  default     = null
  nullable    = true
}

variable "service_account_scopes" {
  description = "OAuth scopes for the instance service account. IAM roles remain the authorization boundary."
  type        = list(string)
  default = [
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring.write",
  ]
}

variable "labels" {
  description = "Labels applied to the gateway."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Protect the gateway from accidental deletion."
  type        = bool
  default     = false
}
