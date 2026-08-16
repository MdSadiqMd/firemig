resource "google_project_service" "resource_manager" {
  count = var.enable_required_apis ? 1 : 0

  project            = var.project_id
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  count = var.enable_required_apis ? 1 : 0

  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_storage_bucket" "terraform_state" {
  project                     = var.project_id
  name                        = var.bucket_name
  location                    = var.location
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels = merge(var.labels, {
    managed-by = "terraform"
    purpose    = "terraform-state"
  })

  versioning {
    enabled = true
  }

  dynamic "encryption" {
    for_each = var.kms_key_name == null ? [] : [var.kms_key_name]
    content {
      default_kms_key_name = encryption.value
    }
  }

  depends_on = [
    google_project_service.resource_manager,
    google_project_service.storage,
  ]
}
