output "external_ip" {
  value = module.environment.external_ip
}

output "vm_name" {
  value = module.environment.vm_name
}

output "service_account_email" {
  value = module.environment.service_account_email
}

output "acme_zone_name" {
  value = module.environment.acme_zone_name
}

output "ssh_command" {
  value = module.environment.ssh_command
}
