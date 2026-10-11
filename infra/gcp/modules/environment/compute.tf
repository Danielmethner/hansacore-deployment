resource "google_compute_address" "ip" {
  project = var.project_id
  name    = "${local.prefix}-ip"
  region  = var.region
}

# Separate disk so the Postgres data lives outside the boot disk.
# scripts/bootstrap-vm.sh formats it (only if empty) and mounts it at
# /mnt/disks/postgres-data, which the gcp-vm Kustomize component uses as hostPath.
resource "google_compute_disk" "postgres_data" {
  project = var.project_id
  name    = "${local.prefix}-postgres-data"
  zone    = var.zone
  type    = "pd-ssd"
  size    = var.data_disk_size_gb
}

resource "google_compute_instance" "vm" {
  project      = var.project_id
  name         = "${local.prefix}-vm"
  zone         = var.zone
  machine_type = var.machine_type
  tags         = [local.web_tag]

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = var.boot_image
      size  = var.boot_disk_size_gb
      type  = "pd-balanced"
    }
  }

  # device_name makes the disk appear as /dev/disk/by-id/google-postgres-data.
  attached_disk {
    source      = google_compute_disk.postgres_data.id
    device_name = "postgres-data"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id

    access_config {
      nat_ip = google_compute_address.ip.address
    }
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  depends_on = [
    google_project_iam_member.vm_log_writer,
    google_project_iam_member.vm_metric_writer,
  ]
}
