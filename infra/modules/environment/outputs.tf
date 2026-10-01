output "external_ip" {
  value = google_compute_address.ip.address
}

output "vm_name" {
  value = google_compute_instance.vm.name
}

output "zone" {
  value = var.zone
}

output "service_account_email" {
  value = google_service_account.vm.email
}

output "acme_zone_name" {
  description = "Goes into hostedZoneName of the overlay's ClusterIssuers."
  value       = google_dns_managed_zone.acme.name
}

output "ssh_command" {
  value = "gcloud compute ssh ${google_compute_instance.vm.name} --project=${var.project_id} --zone=${var.zone} --tunnel-through-iap"
}
