variable "env" {
  description = "Environment name, used in every resource name (e.g. uat, sit, prod)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase letters/digits, starting with a letter."
  }
}

variable "project_id" {
  description = "Project that holds this environment's VM, network and service account."
  type        = string
}

variable "shared_project_id" {
  description = "Shared project with the main DNS zone, the ACME zones and the Artifact Registry repo."
  type        = string
  default     = "hansacore"
}

variable "region" {
  type    = string
  default = "europe-west6"
}

variable "zone" {
  type    = string
  default = "europe-west6-a"
}

variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "boot_image" {
  description = "Boot image or image family for the VM."
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "boot_disk_size_gb" {
  type    = number
  default = 20
}

variable "data_disk_size_gb" {
  description = "Size of the pd-ssd disk that holds the Postgres data directory."
  type        = number
  default     = 20
}

variable "subnet_cidr" {
  description = "Primary range of the environment's subnet. Keep it unique per environment."
  type        = string
}

variable "domain" {
  description = "Apex domain served by the main DNS zone (no trailing dot)."
  type        = string
  default     = "hansacore.com"
}

variable "main_dns_zone_name" {
  description = "Cloud DNS managed zone for the apex domain, in the shared project."
  type        = string
  default     = "hansacore-zone"
}

variable "hostnames" {
  description = "The environment's public hostnames (portal, ERP, auth). Must match overlays/<env>/hansacore-env.properties."
  type        = list(string)

  validation {
    condition     = alltrue([for h in var.hostnames : endswith(h, ".hansacore.com")])
    error_message = "Every hostname must be under hansacore.com."
  }
}

variable "dns_ttl" {
  type    = number
  default = 300
}

variable "artifact_registry_location" {
  type    = string
  default = "europe-west6"
}

variable "artifact_registry_repository" {
  type    = string
  default = "hansacore-images"
}

variable "ssh_members" {
  description = "Principals allowed to SSH to the VM through IAP with sudo (e.g. user:gcp-admin@hansacore.com)."
  type        = list(string)
}
