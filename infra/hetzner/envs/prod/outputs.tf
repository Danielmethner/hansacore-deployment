output "ipv4_address" {
  value = module.server.ipv4_address
}

output "private_ip" {
  value = module.server.private_ip
}

output "server_name" {
  value = module.server.server_name
}

output "ssh_command" {
  value = "hcloud server ssh ${module.server.server_name}"
}

output "nameservers" {
  value = data.terraform_remote_state.shared.outputs.nameservers
}
