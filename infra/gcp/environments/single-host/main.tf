locals {
  environment_labels = merge(var.labels, {
    environment = "single-host"
    managed-by  = "terraform"
  })
  host_tag = "${var.name_prefix}-single-runtime"
}

resource "google_project_service" "compute" {
  count = var.enable_required_apis ? 1 : 0

  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

module "network" {
  source = "../../modules/network"

  project_id = var.project_id
  name       = "${var.name_prefix}-single"
  subnets = {
    runtime = {
      region = var.region
      cidr   = var.subnet_cidr
    }
  }

  depends_on = [google_project_service.compute]
}

module "runtime" {
  source = "../../modules/nested-kvm-host"

  project_id            = var.project_id
  name                  = "${var.name_prefix}-runtime"
  zone                  = var.zone
  subnetwork            = module.network.subnet_ids.runtime
  machine_type          = var.machine_type
  min_cpu_platform      = var.min_cpu_platform
  data_disk_size_gb     = var.data_disk_size_gb
  data_mount_point      = "/var/lib/runable"
  assign_public_ip      = true
  network_tags          = [local.host_tag]
  service_account_email = var.service_account_email
  deletion_protection   = var.deletion_protection
  labels                = local.environment_labels
  app_directories = concat(
    ["/etc/runable", "/var/lib/runable/artifacts"],
    [for id in var.logical_worker_ids : "/var/lib/runable/workers/${id}"]
  )
  metadata = {
    runable-environment = "single-host"
    runable-roles       = jsonencode(["coordinator", "proxy", "worker"])
    runable-logical-workers = jsonencode({
      workers = [for id in var.logical_worker_ids : {
        id             = id
        artifact_path  = "/var/lib/runable/artifacts"
        workspace_path = "/var/lib/runable/workers/${id}"
      }]
    })
  }
}

resource "google_compute_firewall" "public_services" {
  count = length(var.allowed_client_cidrs) > 0 ? 1 : 0

  project       = var.project_id
  name          = "${var.name_prefix}-single-clients"
  network       = module.network.network_id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = var.allowed_client_cidrs
  target_tags   = [local.host_tag]

  allow {
    protocol = "tcp"
    ports    = [for port in var.public_service_ports : tostring(port)]
  }
}

resource "google_compute_firewall" "iap_ssh" {
  project       = var.project_id
  name          = "${var.name_prefix}-single-iap-ssh"
  network       = module.network.network_id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"]
  target_tags   = [local.host_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
