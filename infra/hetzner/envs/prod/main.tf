data "terraform_remote_state" "shared" {
  backend = "local"

  config = {
    path = abspath("${path.module}/../../shared/terraform.tfstate")
  }
}

module "server" {
  source = "../../modules/server"

  name        = "hansacore-prod"
  env         = "prod"
  server_type = var.server_type
  backups     = var.backups
  private_ip  = "10.10.1.30"
  ssh_key_id  = data.terraform_remote_state.shared.outputs.ssh_key_id
  firewall_id = data.terraform_remote_state.shared.outputs.firewall_id
  network_id  = data.terraform_remote_state.shared.outputs.network_id
}

resource "hcloud_zone_rrset" "a" {
  for_each = toset(var.record_names)

  zone = data.terraform_remote_state.shared.outputs.zone_name
  name = each.value
  type = "A"
  ttl  = 300

  records = [
    { value = module.server.ipv4_address },
  ]
}
