variable "project_id" {
  description = "Globally unique project ID for UAT. Cannot be reused for 30 days after deletion."
  type        = string
  default     = "hansacore-uat"
}

variable "project_name" {
  type    = string
  default = "HansaCore UAT"
}

variable "folder_id" {
  description = "Numeric ID of the nonprod folder (gcloud resource-manager folders list --organization=ORG_ID)."
  type        = string
}

variable "billing_account" {
  description = "Billing account ID, format XXXXXX-XXXXXX-XXXXXX (gcloud billing accounts list)."
  type        = string
}

variable "shared_project_id" {
  type    = string
  default = "hansacore"
}

variable "budget_amount" {
  description = "Monthly budget for this project, in the billing account's currency."
  type        = number
  default     = 100
}

variable "allow_vm_external_ip" {
  description = "Set to true if the organization enforces compute.vmExternalIpAccess (check with gcloud org-policies list). Allows exactly the UAT VM to have a public IP."
  type        = bool
  default     = false
}

variable "vm_zone" {
  type    = string
  default = "europe-west6-a"
}

variable "vm_name" {
  description = "Must match the VM name the environment module creates (hansacore-<env>-vm)."
  type        = string
  default     = "hansacore-uat-vm"
}
