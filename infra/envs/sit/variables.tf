variable "project_id" {
  description = "Created by infra/projects/sit."
  type        = string
  default     = "hansacore-sit"
}

variable "ssh_members" {
  description = "Principals allowed to SSH to the VM through IAP with sudo."
  type        = list(string)
}
