variable "name" {
  description = "Server name, also the cloud-init hostname (hansacore-sit, hansacore-uat, hansacore-prod)."
  type        = string
}

variable "env" {
  description = "Environment label stored on the server and its Primary IP."
  type        = string
}

variable "server_type" {
  description = "Hetzner server type. Confirm the monthly price with `hcloud server-type describe` before apply."
  type        = string
}

variable "backups" {
  description = "Enable Hetzner automatic backups (about 20% of the server price). The local disk is deleted with the server."
  type        = bool
  default     = false
}

variable "private_ip" {
  description = "Address on the shared eu-central subnet 10.10.1.0/24."
  type        = string
}

variable "ssh_key_id" {
  description = "ID of the hcloud_ssh_key from infra/shared."
  type        = string
}

variable "firewall_id" {
  description = "ID of the shared Hetzner Cloud firewall."
  type        = number
}

variable "network_id" {
  description = "ID of the shared private network."
  type        = number
}

variable "location" {
  description = "Hetzner location. nbg1 is Nuremberg."
  type        = string
  default     = "nbg1"
}

variable "image" {
  description = "Server image."
  type        = string
  default     = "ubuntu-24.04"
}

variable "cert_manager_version" {
  description = "cert-manager release installed on first boot. Matches scripts/bootstrap-vm.sh."
  type        = string
  default     = "v1.21.2"
}
