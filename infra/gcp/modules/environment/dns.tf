data "google_dns_managed_zone" "main" {
  project = var.shared_project_id
  name    = var.main_dns_zone_name
}

resource "google_dns_record_set" "a" {
  for_each = toset(var.hostnames)

  project      = var.shared_project_id
  managed_zone = data.google_dns_managed_zone.main.name
  name         = "${each.value}."
  type         = "A"
  ttl          = var.dns_ttl
  rrdatas      = [google_compute_address.ip.address]
}

# Dedicated zone for ACME DNS-01 challenges, so the VM's service account never
# needs write access to the main zone. force_destroy removes leftover
# challenge TXT records on terraform destroy.
resource "google_dns_managed_zone" "acme" {
  project       = var.shared_project_id
  name          = "${local.prefix}-acme-zone"
  dns_name      = "acme-${var.env}.${var.domain}."
  description   = "ACME DNS-01 challenges for the ${var.env} environment."
  force_destroy = true
}

resource "google_dns_record_set" "acme_delegation" {
  project      = var.shared_project_id
  managed_zone = data.google_dns_managed_zone.main.name
  name         = google_dns_managed_zone.acme.dns_name
  type         = "NS"
  ttl          = var.dns_ttl
  rrdatas      = google_dns_managed_zone.acme.name_servers
}

# _acme-challenge.<host> -> <label>.acme-<env>.<domain>; cert-manager follows
# it (cnameStrategy: Follow) and writes the TXT record in the ACME zone.
resource "google_dns_record_set" "acme_challenge_cname" {
  for_each = local.acme_labels

  project      = var.shared_project_id
  managed_zone = data.google_dns_managed_zone.main.name
  name         = "_acme-challenge.${each.key}."
  type         = "CNAME"
  ttl          = var.dns_ttl
  rrdatas      = ["${each.value}.${google_dns_managed_zone.acme.dns_name}"]
}
