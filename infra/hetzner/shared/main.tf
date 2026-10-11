resource "hcloud_ssh_key" "admin" {
  name       = "hansacore-admin"
  public_key = var.ssh_public_key
}

resource "hcloud_firewall" "web" {
  name = "hansacore"

  # Nothing else is allowed in. The k3s API (6443) stays closed.
  rule {
    description = "HTTP for Traefik and Let's Encrypt HTTP-01"
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  rule {
    description = "HTTPS"
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  rule {
    description = "SSH, public-key only (cloud-init disables password auth)"
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = var.ssh_allowed_cidrs
  }
}

resource "hcloud_network" "private" {
  name     = "hansacore"
  ip_range = "10.10.0.0/16"
}

resource "hcloud_network_subnet" "nbg1" {
  network_id   = hcloud_network.private.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.10.1.0/24"
}

resource "hcloud_zone" "hansacore" {
  name              = var.zone_name
  mode              = "primary"
  ttl               = 300
  delete_protection = true

  labels = {
    app = "hansacore"
  }
}
