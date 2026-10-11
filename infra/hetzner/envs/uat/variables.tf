variable "server_type" {
  description = "Compute-optimized AMD EPYC 2 vCPU / 4 GB / 80 GB NVMe (or cpx32 for 8 GB). Available in nbg1 (Nuremberg)."
  type        = string
  default     = "cpx22"
}

variable "backups" {
  description = "Hetzner automatic backups. Off for UAT; prod turns them on."
  type        = bool
  default     = false
}

variable "record_names" {
  description = "Relative names in the hansacore.com zone. Must match k8s/overlays/uat hostnames."
  type        = list(string)
  default     = ["uat", "uat.erp", "uat.auth"]
}
