resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = "${local.prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  project                  = var.project_id
  name                     = "${local.prefix}-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

resource "google_compute_firewall" "allow_web" {
  project     = var.project_id
  name        = "${local.prefix}-allow-web"
  network     = google_compute_network.vpc.id
  description = "HTTP/HTTPS from the internet to Traefik."
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.web_tag]
}

resource "google_compute_firewall" "allow_iap_ssh" {
  project     = var.project_id
  name        = "${local.prefix}-allow-iap-ssh"
  network     = google_compute_network.vpc.id
  description = "SSH only from Google's IAP TCP forwarding range; port 22 is not open to the internet."
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = [local.web_tag]
}
