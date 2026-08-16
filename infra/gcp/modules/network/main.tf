resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = var.name
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "this" {
  for_each = var.subnets

  project                  = var.project_id
  name                     = "${var.name}-${each.key}"
  region                   = each.value.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = each.value.cidr
  private_ip_google_access = each.value.private_google_access
}

resource "google_compute_router" "this" {
  for_each = var.nat_regions

  project = var.project_id
  name    = "${var.name}-${each.key}-router"
  region  = each.key
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  for_each = var.nat_regions

  project                            = var.project_id
  name                               = "${var.name}-${each.key}-nat"
  region                             = each.key
  router                             = google_compute_router.this[each.key].name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
