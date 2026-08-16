variable "project_id" {
  description = "GCP project containing the host."
  type        = string
}

variable "name" {
  description = "Host instance name."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name)) && length(var.name) <= 63
    error_message = "name must be a valid GCP resource name with at most 63 characters."
  }
}

variable "zone" {
  description = "Zone in which to create the host and artifact disk."
  type        = string
}

variable "subnetwork" {
  description = "Fully qualified subnetwork ID."
  type        = string
}

variable "machine_type" {
  description = "Intel-supported machine type for nested virtualization."
  type        = string
  default     = "n2-standard-8"

  validation {
    condition     = can(regex("^(n1|n2|c2|c3|c4)-", var.machine_type))
    error_message = "machine_type must be from an Intel-backed Compute Engine family that supports nested virtualization; n2-standard-8 is recommended."
  }
}

variable "min_cpu_platform" {
  description = "Minimum Intel CPU platform requested from Compute Engine. This is not a snapshot compatibility guarantee."
  type        = string
  default     = "Intel Cascade Lake"

  validation {
    condition     = startswith(var.min_cpu_platform, "Intel ")
    error_message = "min_cpu_platform must select an Intel platform for x86_64 Firecracker hosts."
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

variable "boot_disk_type" {
  description = "Boot persistent disk type."
  type        = string
  default     = "pd-balanced"
}

variable "data_disk_size_gb" {
  description = "Artifact and Firecracker image disk size in GiB."
  type        = number
  default     = 250

  validation {
    condition     = var.data_disk_size_gb >= 100
    error_message = "data_disk_size_gb must be at least 100 GiB for Firecracker artifacts."
  }
}

variable "data_disk_type" {
  description = "Artifact persistent disk type."
  type        = string
  default     = "pd-balanced"
}

variable "data_disk_device_name" {
  description = "Stable device name used by the startup script."
  type        = string
  default     = "runable-data"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.data_disk_device_name))
    error_message = "data_disk_device_name must contain lowercase letters, digits, and hyphens."
  }
}

variable "data_mount_point" {
  description = "Mount point for the persistent artifact disk."
  type        = string
  default     = "/var/lib/runable"

  validation {
    condition     = can(regex("^/[A-Za-z0-9._/-]+$", var.data_mount_point))
    error_message = "data_mount_point must be an absolute path without whitespace."
  }
}

variable "app_user" {
  description = "Unprivileged runtime user created during startup."
  type        = string
  default     = "runable"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,30}$", var.app_user))
    error_message = "app_user must be a valid Linux user name."
  }
}

variable "app_group" {
  description = "Primary runtime group created during startup."
  type        = string
  default     = "runable"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,30}$", var.app_group))
    error_message = "app_group must be a valid Linux group name."
  }
}

variable "app_directories" {
  description = "Additional directories created and owned by the runtime user."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for path in var.app_directories : can(regex("^/[A-Za-z0-9._/-]+$", path))])
    error_message = "app_directories entries must be absolute paths without whitespace."
  }
}

variable "assign_public_ip" {
  description = "Create and attach a static regional external IPv4 address."
  type        = bool
  default     = false
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
  description = "Labels applied to the instance and disks."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Protect the instance from accidental deletion."
  type        = bool
  default     = false
}
