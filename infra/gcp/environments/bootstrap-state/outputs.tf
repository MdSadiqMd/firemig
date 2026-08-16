output "bucket_name" {
  description = "Versioned GCS state bucket name."
  value       = google_storage_bucket.terraform_state.name
}

output "bucket_url" {
  description = "GCS URL of the Terraform state bucket."
  value       = google_storage_bucket.terraform_state.url
}

output "single_host_backend_init" {
  description = "Backend initialization command for the single-host root."
  value       = "terraform init -backend-config=bucket=${google_storage_bucket.terraform_state.name} -backend-config=prefix=runable/single-host"
}

output "two_region_backend_init" {
  description = "Backend initialization command for the two-region root."
  value       = "terraform init -backend-config=bucket=${google_storage_bucket.terraform_state.name} -backend-config=prefix=runable/two-region"
}
