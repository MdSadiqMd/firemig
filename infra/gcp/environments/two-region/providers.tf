provider "google" {
  project = var.project_id
  region  = var.region_a
  zone    = var.gateway_zone
}
