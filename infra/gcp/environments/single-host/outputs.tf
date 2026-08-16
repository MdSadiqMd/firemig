output "instance" {
  description = "Runtime instance details for deploy tooling."
  value = {
    id         = module.runtime.instance_id
    name       = module.runtime.instance_name
    zone       = module.runtime.zone
    private_ip = module.runtime.private_ip
    public_ip  = module.runtime.public_ip
  }
}

output "public_ip" {
  description = "Static runtime public IPv4 address."
  value       = module.runtime.public_ip
}

output "data_disk_id" {
  description = "Persistent artifact disk ID."
  value       = module.runtime.data_disk_id
}

output "network" {
  description = "Network identifiers for automation."
  value = {
    id      = module.network.network_id
    name    = module.network.network_name
    subnets = module.network.subnet_ids
  }
}

output "logical_worker_ids" {
  description = "Logical workers configured in instance metadata."
  value       = var.logical_worker_ids
}

output "iap_ssh_command" {
  description = "IAP-only SSH command for the runtime host."
  value       = "gcloud compute ssh ${module.runtime.instance_name} --project ${var.project_id} --zone ${var.zone} --tunnel-through-iap"
}
