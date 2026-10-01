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
    prefix = "envs/uat"
  }
}

provider "google" {
  project = var.project_id
  region  = "europe-west6"
}
