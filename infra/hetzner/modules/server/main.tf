resource "hcloud_primary_ip" "ipv4" {
  name        = "${var.name}-ipv4"
  type        = "ipv4"
  auto_delete = false
  location    = var.location

  labels = {
    app = "hansacore"
    env = var.env
  }
}

resource "hcloud_server" "vm" {
  name         = var.name
  server_type  = var.server_type
  image        = var.image
  location     = var.location
  ssh_keys     = [var.ssh_key_id]
  firewall_ids = [var.firewall_id]
  backups      = var.backups
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname             = var.name
    cert_manager_version = var.cert_manager_version
  })

  labels = {
    app = "hansacore"
    env = var.env
  }

  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.ipv4.id
    ipv6_enabled = true
  }

  # cloud-init runs once. Editing user_data later must not replace the
  # server: the Postgres disk is the server's local NVMe and dies with it.
  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "hcloud_server_network" "private" {
  # The server id is a string in this provider; the attachment attribute is a number.
  server_id  = tonumber(hcloud_server.vm.id)
  network_id = var.network_id
  ip         = var.private_ip
}
