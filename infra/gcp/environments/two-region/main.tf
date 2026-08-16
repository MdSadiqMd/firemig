locals {
  environment_labels = merge(var.labels, {
    environment = "two-region"
    managed-by  = "terraform"
  })
  gateway_tag = "${var.name_prefix}-gateway"
  worker_tag  = "${var.name_prefix}-worker"
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
  name       = "${var.name_prefix}-regional"
  subnets = {
    region-a = {
      region = var.region_a
      cidr   = var.subnet_a_cidr
    }
    region-b = {
      region = var.region_b
      cidr   = var.subnet_b_cidr
    }
  }
  nat_regions = [var.region_a, var.region_b]

  depends_on = [google_project_service.compute]
}

module "gateway" {
  source = "../../modules/gateway"

  project_id            = var.project_id
  name                  = "${var.name_prefix}-gateway"
  zone                  = var.gateway_zone
  subnetwork            = module.network.subnet_ids["region-a"]
  machine_type          = var.gateway_machine_type
  min_cpu_platform      = var.min_cpu_platform
  network_tags          = [local.gateway_tag]
  service_account_email = var.gateway_service_account_email
  deletion_protection   = var.deletion_protection
  labels                = local.environment_labels
  metadata = {
    runable-environment = "two-region"
    runable-roles       = jsonencode(["gateway", "coordinator", "proxy"])
    runable-workers = jsonencode([
      { id = "worker-a", region = var.region_a },
      { id = "worker-b", region = var.region_b },
    ])
  }
}

module "worker_a" {
  source = "../../modules/nested-kvm-host"

  project_id            = var.project_id
  name                  = "${var.name_prefix}-worker-a"
  zone                  = var.worker_a_zone
  subnetwork            = module.network.subnet_ids["region-a"]
  machine_type          = var.worker_machine_type
  min_cpu_platform      = var.min_cpu_platform
  data_disk_size_gb     = var.worker_data_disk_size_gb
  data_mount_point      = "/var/lib/runable"
  network_tags          = [local.worker_tag]
  service_account_email = var.worker_service_account_email
  deletion_protection   = var.deletion_protection
  labels                = merge(local.environment_labels, { worker = "a" })
  app_directories       = ["/etc/runable", "/var/lib/runable/artifacts", "/var/lib/runable/workspaces"]
  metadata = {
    runable-environment        = "two-region"
    runable-roles              = jsonencode(["worker"])
    runable-worker-id          = "worker-a"
    runable-control-private-ip = module.gateway.private_ip
  }
}

module "worker_b" {
  source = "../../modules/nested-kvm-host"

  project_id            = var.project_id
  name                  = "${var.name_prefix}-worker-b"
  zone                  = var.worker_b_zone
  subnetwork            = module.network.subnet_ids["region-b"]
  machine_type          = var.worker_machine_type
  min_cpu_platform      = var.min_cpu_platform
  data_disk_size_gb     = var.worker_data_disk_size_gb
  data_mount_point      = "/var/lib/runable"
  network_tags          = [local.worker_tag]
  service_account_email = var.worker_service_account_email
  deletion_protection   = var.deletion_protection
  labels                = merge(local.environment_labels, { worker = "b" })
  app_directories       = ["/etc/runable", "/var/lib/runable/artifacts", "/var/lib/runable/workspaces"]
  metadata = {
    runable-environment        = "two-region"
    runable-roles              = jsonencode(["worker"])
    runable-worker-id          = "worker-b"
    runable-control-private-ip = module.gateway.private_ip
  }
}

resource "google_compute_firewall" "public_services" {
  count = length(var.allowed_client_cidrs) > 0 ? 1 : 0

  project       = var.project_id
  name          = "${var.name_prefix}-gateway-clients"
  network       = module.network.network_id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = var.allowed_client_cidrs
  target_tags   = [local.gateway_tag]

  allow {
    protocol = "tcp"
    ports    = [for port in var.public_service_ports : tostring(port)]
  }
}

resource "google_compute_firewall" "iap_ssh" {
  project       = var.project_id
  name          = "${var.name_prefix}-iap-ssh"
  network       = module.network.network_id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"]
  target_tags   = [local.gateway_tag, local.worker_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "private_agents" {
  project     = var.project_id
  name        = "${var.name_prefix}-private-agents"
  network     = module.network.network_id
  direction   = "INGRESS"
  priority    = 1000
  source_tags = [local.worker_tag]
  target_tags = [local.gateway_tag]

  allow {
    protocol = "tcp"
    ports    = [for port in var.agent_service_ports : tostring(port)]
  }
}

resource "google_compute_firewall" "private_worker_admin" {
  project     = var.project_id
  name        = "${var.name_prefix}-private-worker-admin"
  network     = module.network.network_id
  direction   = "INGRESS"
  priority    = 1000
  source_tags = [local.gateway_tag]
  target_tags = [local.worker_tag]

  allow {
    protocol = "tcp"
    ports    = [for port in var.worker_admin_ports : tostring(port)]
  }
}

resource "google_compute_firewall" "private_worker_peer" {
  project     = var.project_id
  name        = "${var.name_prefix}-private-worker-peer"
  network     = module.network.network_id
  direction   = "INGRESS"
  priority    = 1000
  source_tags = [local.worker_tag]
  target_tags = [local.worker_tag]

  allow {
    protocol = "tcp"
    ports    = [for port in var.worker_peer_ports : tostring(port)]
  }
}
