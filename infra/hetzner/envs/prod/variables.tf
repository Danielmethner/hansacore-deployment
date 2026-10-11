variable "server_type" {
  description = "Compute-optimized AMD EPYC 4 vCPU / 8 GB / 160 GB NVMe. Available in nbg1 (Nuremberg)."
  type        = string
  default     = "cpx32"
}

variable "backups" {
  description = "Hetzner automatic backups. On for prod because the local NVMe is deleted with the server."
  type        = bool
  default     = true
}

variable "record_names" {
  description = "Relative names in the hansacore.com zone. @ is the apex. Must match k8s/overlays/prod hostnames."
  type        = list(string)
  default     = ["@", "erp", "auth"]
}
