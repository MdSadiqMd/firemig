output "instance_id" {
  description = "Compute Engine instance ID."
  value       = google_compute_instance.this.instance_id
}

output "instance_name" {
  description = "Compute Engine instance name."
  value       = google_compute_instance.this.name
}

output "self_link" {
  description = "Fully qualified instance self link."
  value       = google_compute_instance.this.self_link
}

output "private_ip" {
  description = "Primary internal IPv4 address."
  value       = google_compute_instance.this.network_interface[0].network_ip
}

output "public_ip" {
  description = "Static external IPv4 address."
  value       = google_compute_address.this.address
}

output "zone" {
  description = "Gateway zone."
  value       = google_compute_instance.this.zone
}
