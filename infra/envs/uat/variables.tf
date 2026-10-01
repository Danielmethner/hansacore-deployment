variable "project_id" {
  description = "Created by infra/projects/uat."
  type        = string
  default     = "hansacore-uat"
}

variable "ssh_members" {
  description = "Principals allowed to SSH to the VM through IAP with sudo."
  type        = list(string)
}
