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
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name_prefix)) && length(var.name_prefix) <= 25
    error_message = "name_prefix must be a valid lowercase GCP resource prefix with at most 25 characters."
  }
}

variable "region_a" {
  description = "Region containing the gateway and worker A."
  type        = string
  default     = "us-central1"

  validation {
    condition     = var.region_a != var.region_b
    error_message = "region_a and region_b must be different regions."
  }
}

variable "region_b" {
  description = "Region containing worker B."
  type        = string
  default     = "us-east1"
}

variable "gateway_zone" {
  description = "Gateway zone in region A."
  type        = string
  default     = "us-central1-a"

  validation {
    condition     = startswith(var.gateway_zone, "${var.region_a}-")
    error_message = "gateway_zone must belong to region_a."
  }
}

variable "worker_a_zone" {
  description = "Worker A zone in region A."
  type        = string
  default     = "us-central1-b"

  validation {
    condition     = startswith(var.worker_a_zone, "${var.region_a}-")
    error_message = "worker_a_zone must belong to region_a."
  }
}

variable "worker_b_zone" {
  description = "Worker B zone in region B."
  type        = string
  default     = "us-east1-b"

  validation {
    condition     = startswith(var.worker_b_zone, "${var.region_b}-")
    error_message = "worker_b_zone must belong to region_b."
  }
}

variable "subnet_a_cidr" {
  description = "CIDR for the region A subnet."
  type        = string
  default     = "10.40.0.0/24"

  validation {
    condition     = can(cidrnetmask(var.subnet_a_cidr))
    error_message = "subnet_a_cidr must be a valid CIDR."
  }
}

variable "subnet_b_cidr" {
  description = "CIDR for the region B subnet."
  type        = string
  default     = "10.41.0.0/24"

  validation {
    condition     = can(cidrnetmask(var.subnet_b_cidr)) && var.subnet_b_cidr != var.subnet_a_cidr
    error_message = "subnet_b_cidr must be valid and different from subnet_a_cidr."
  }
}

variable "allowed_client_cidrs" {
  description = "Client CIDRs allowed to reach gateway API/proxy ports. Empty keeps those ports closed."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_client_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every allowed_client_cidrs entry must be a valid CIDR."
  }
}

variable "public_service_ports" {
  description = "Gateway TCP ports exposed only to allowed_client_cidrs."
  type        = list(number)
  default     = [443]

  validation {
    condition     = length(var.public_service_ports) > 0 && alltrue([for port in var.public_service_ports : port >= 1 && port <= 65535])
    error_message = "public_service_ports must contain valid TCP ports."
  }
}

variable "agent_service_ports" {
  description = "Private gateway ports reachable from workers for agent-to-control traffic."
  type        = list(number)
  default     = [9090]

  validation {
    condition     = length(var.agent_service_ports) > 0 && alltrue([for port in var.agent_service_ports : port >= 1 && port <= 65535])
    error_message = "agent_service_ports must contain valid TCP ports."
  }
}

variable "worker_admin_ports" {
  description = "Private worker administration ports reachable from the gateway."
  type        = list(number)
  default     = [9091]

  validation {
    condition     = length(var.worker_admin_ports) > 0 && alltrue([for port in var.worker_admin_ports : port >= 1 && port <= 65535])
    error_message = "worker_admin_ports must contain valid TCP ports."
  }
}

variable "worker_peer_ports" {
  description = "Private cross-region worker-to-worker TCP ports."
  type        = list(number)
  default     = [9092]

  validation {
    condition     = length(var.worker_peer_ports) > 0 && alltrue([for port in var.worker_peer_ports : port >= 1 && port <= 65535])
    error_message = "worker_peer_ports must contain valid TCP ports."
  }
}

variable "gateway_machine_type" {
  description = "x86_64 gateway machine type."
  type        = string
  default     = "n2-standard-8"
}

variable "worker_machine_type" {
  description = "Intel-supported nested virtualization machine type for both workers."
  type        = string
  default     = "n2-standard-8"
}

variable "min_cpu_platform" {
  description = "Requested Intel CPU floor. It is not proof of Firecracker snapshot compatibility."
  type        = string
  default     = "Intel Cascade Lake"
}

variable "worker_data_disk_size_gb" {
  description = "Persistent Firecracker artifact disk size per worker in GiB."
  type        = number
  default     = 250

  validation {
    condition     = var.worker_data_disk_size_gb >= 100
    error_message = "worker_data_disk_size_gb must be at least 100 GiB."
  }
}

variable "gateway_service_account_email" {
  description = "Optional least-privilege service account for the gateway."
  type        = string
  default     = null
  nullable    = true
}

variable "worker_service_account_email" {
  description = "Optional least-privilege service account shared by workers."
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
  description = "Protect all instances from accidental deletion."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Additional labels applied to instances and disks."
  type        = map(string)
  default     = {}
}
