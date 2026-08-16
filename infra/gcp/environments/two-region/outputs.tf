output "gateway" {
  description = "Gateway details for deploy and DNS tooling."
  value = {
    id         = module.gateway.instance_id
    name       = module.gateway.instance_name
    zone       = module.gateway.zone
    private_ip = module.gateway.private_ip
    public_ip  = module.gateway.public_ip
  }
}

output "gateway_public_ip" {
  description = "Static public IPv4 address for API/proxy DNS."
  value       = module.gateway.public_ip
}

output "workers" {
  description = "Private worker details keyed by worker ID."
  value = {
    worker-a = {
      id           = module.worker_a.instance_id
      name         = module.worker_a.instance_name
      zone         = module.worker_a.zone
      private_ip   = module.worker_a.private_ip
      public_ip    = module.worker_a.public_ip
      data_disk_id = module.worker_a.data_disk_id
    }
    worker-b = {
      id           = module.worker_b.instance_id
      name         = module.worker_b.instance_name
      zone         = module.worker_b.zone
      private_ip   = module.worker_b.private_ip
      public_ip    = module.worker_b.public_ip
      data_disk_id = module.worker_b.data_disk_id
    }
  }
}

output "network" {
  description = "Network, subnet, and NAT identifiers for automation."
  value = {
    id      = module.network.network_id
    name    = module.network.network_name
    subnets = module.network.subnet_ids
    nats    = module.network.nat_names
  }
}

output "iap_ssh_commands" {
  description = "IAP-only SSH commands for all instances."
  value = {
    gateway  = "gcloud compute ssh ${module.gateway.instance_name} --project ${var.project_id} --zone ${var.gateway_zone} --tunnel-through-iap"
    worker-a = "gcloud compute ssh ${module.worker_a.instance_name} --project ${var.project_id} --zone ${var.worker_a_zone} --tunnel-through-iap"
    worker-b = "gcloud compute ssh ${module.worker_b.instance_name} --project ${var.project_id} --zone ${var.worker_b_zone} --tunnel-through-iap"
  }
}
