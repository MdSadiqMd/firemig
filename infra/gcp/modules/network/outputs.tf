output "network_id" {
  description = "Fully qualified VPC network ID."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.this.name
}

output "subnet_ids" {
  description = "Subnet IDs keyed by logical subnet name."
  value       = { for name, subnet in google_compute_subnetwork.this : name => subnet.id }
}

output "subnet_names" {
  description = "Subnet names keyed by logical subnet name."
  value       = { for name, subnet in google_compute_subnetwork.this : name => subnet.name }
}

output "nat_names" {
  description = "Cloud NAT names keyed by region."
  value       = { for region, nat in google_compute_router_nat.this : region => nat.name }
}
