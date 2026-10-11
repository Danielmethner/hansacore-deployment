output "ipv4_address" {
  description = "Primary IPv4. Survives a server rebuild because auto_delete is false and the address is its own resource."
  value       = hcloud_primary_ip.ipv4.ip_address
}

output "server_id" {
  value = hcloud_server.vm.id
}

output "server_name" {
  value = hcloud_server.vm.name
}

output "private_ip" {
  value = hcloud_server_network.private.ip
}
