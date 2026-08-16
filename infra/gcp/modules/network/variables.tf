variable "project_id" {
  description = "GCP project containing the network."
  type        = string

  validation {
    condition     = length(trimspace(var.project_id)) > 0
    error_message = "project_id must not be empty."
  }
}

variable "name" {
  description = "Name of the custom VPC."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name)) && length(var.name) <= 63
    error_message = "name must be a valid GCP resource name with at most 63 characters."
  }
}

variable "subnets" {
  description = "Regional subnets keyed by a stable logical name."
  type = map(object({
    region                = string
    cidr                  = string
    private_google_access = optional(bool, true)
  }))

  validation {
    condition     = length(var.subnets) > 0 && alltrue([for subnet in values(var.subnets) : can(cidrnetmask(subnet.cidr))])
    error_message = "At least one subnet is required and every subnet CIDR must be valid."
  }
}

variable "nat_regions" {
  description = "Regions in which to create a Cloud Router and Cloud NAT."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for region in var.nat_regions : contains([for subnet in values(var.subnets) : subnet.region], region)])
    error_message = "Each NAT region must contain one of the configured subnets."
  }
}
