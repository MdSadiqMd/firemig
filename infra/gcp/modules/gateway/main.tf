locals {
  region = join("-", slice(split("-", var.zone), 0, length(split("-", var.zone)) - 1))
}

resource "google_compute_address" "this" {
  project      = var.project_id
  name         = "${var.name}-ipv4"
  region       = local.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}

resource "google_compute_instance" "this" {
  project                   = var.project_id
  name                      = var.name
  zone                      = var.zone
  machine_type              = var.machine_type
  min_cpu_platform          = var.min_cpu_platform
  allow_stopping_for_update = true
  deletion_protection       = var.deletion_protection
  tags                      = var.network_tags
  labels                    = var.labels

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = "projects/debian-cloud/global/images/family/debian-12"
      size   = var.boot_disk_size_gb
      type   = "pd-balanced"
      labels = var.labels
    }
  }

  network_interface {
    subnetwork = var.subnetwork

    access_config {
      nat_ip       = google_compute_address.this.address
      network_tier = "PREMIUM"
    }
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
    provisioning_model  = "STANDARD"
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = true
    enable_vtpm                 = true
  }

  metadata = merge(var.metadata, {
    block-project-ssh-keys = "TRUE"
    enable-oslogin         = "TRUE"
  })

  metadata_startup_script = templatefile("${path.module}/startup.sh.tftpl", {
    app_directories = var.app_directories
    app_group       = var.app_group
    app_user        = var.app_user
  })

  service_account {
    email  = var.service_account_email
    scopes = var.service_account_scopes
  }
}
