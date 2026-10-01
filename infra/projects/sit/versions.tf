terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  backend "gcs" {
    bucket = "hansacore-tfstate"
    prefix = "projects/sit"
  }
}

# Budgets (and org policies) are called with user credentials; those APIs
# need a quota project, which is the shared project.
provider "google" {
  user_project_override = true
  billing_project       = var.shared_project_id
}
