output "ssh_key_id" {
  value = hcloud_ssh_key.admin.id
}

output "firewall_id" {
  description = "Numeric id. firewall_ids on the server is a set of numbers; the resource id is a string."
  value       = tonumber(hcloud_firewall.web.id)
}

output "network_id" {
  description = "Numeric id. hcloud_server_network.network_id is a number; the resource id is a string."
  value       = tonumber(hcloud_network.private.id)
}

output "zone_name" {
  value = hcloud_zone.hansacore.name
}

output "zone_id" {
  value = hcloud_zone.hansacore.id
}

output "nameservers" {
  description = "Set these at the registrar (Squarespace) after SIT A records exist."
  value       = hcloud_zone.hansacore.authoritative_nameservers.assigned
}
