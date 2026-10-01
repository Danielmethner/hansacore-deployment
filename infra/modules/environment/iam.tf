resource "google_service_account" "vm" {
  project      = var.project_id
  account_id   = "${local.prefix}-vm"
  display_name = "HansaCore ${upper(var.env)} VM"
  description  = "Attached to the ${var.env} VM. No keys; used through the metadata server."
}

resource "google_project_iam_member" "vm_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.vm.member
}

resource "google_project_iam_member" "vm_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = google_service_account.vm.member
}

# cert-manager's DNS-01 solver: may edit only this environment's ACME zone,
# never the main zone.
resource "google_dns_managed_zone_iam_member" "vm_acme_dns_admin" {
  project      = var.shared_project_id
  managed_zone = google_dns_managed_zone.acme.name
  role         = "roles/dns.admin"
  member       = google_service_account.vm.member
}

resource "google_artifact_registry_repository_iam_member" "vm_image_reader" {
  project    = var.shared_project_id
  location   = var.artifact_registry_location
  repository = var.artifact_registry_repository
  role       = "roles/artifactregistry.reader"
  member     = google_service_account.vm.member
}

# SSH through IAP with OS Login and sudo.
resource "google_project_iam_member" "ssh_iap_tunnel" {
  for_each = toset(var.ssh_members)

  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = each.value
}

resource "google_project_iam_member" "ssh_os_admin_login" {
  for_each = toset(var.ssh_members)

  project = var.project_id
  role    = "roles/compute.osAdminLogin"
  member  = each.value
}

# OS Login on a VM with an attached service account also requires
# permission to act as that service account.
resource "google_service_account_iam_member" "ssh_sa_user" {
  for_each = toset(var.ssh_members)

  service_account_id = google_service_account.vm.name
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}
