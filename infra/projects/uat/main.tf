# Long-lived layer for UAT: the project itself, its APIs and its budget.
# Kept apart from infra/envs/uat so the environment can be destroyed and
# recreated without deleting the project (a deleted project ID stays
# reserved for 30 days).

resource "google_project" "this" {
  project_id          = var.project_id
  name                = var.project_name
  folder_id           = var.folder_id
  billing_account     = var.billing_account
  auto_create_network = false
  deletion_policy     = "PREVENT"
}

locals {
  services = concat(
    [
      "compute.googleapis.com",
      "iap.googleapis.com",
      "oslogin.googleapis.com",
      "iam.googleapis.com",
      "cloudresourcemanager.googleapis.com",
      "logging.googleapis.com",
      "monitoring.googleapis.com",
    ],
    var.allow_vm_external_ip ? ["orgpolicy.googleapis.com"] : [],
  )
}

resource "google_project_service" "services" {
  for_each = toset(local.services)

  project            = google_project.this.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_billing_budget" "monthly" {
  billing_account = var.billing_account
  display_name    = "${var.project_id} monthly"

  budget_filter {
    projects = ["projects/${google_project.this.number}"]
  }

  amount {
    specified_amount {
      units = tostring(var.budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }
}

# Only if the organization blocks external IPs on VMs: allow exactly the UAT VM.
resource "google_org_policy_policy" "vm_external_ip" {
  count = var.allow_vm_external_ip ? 1 : 0

  name   = "projects/${google_project.this.project_id}/policies/compute.vmExternalIpAccess"
  parent = "projects/${google_project.this.project_id}"

  spec {
    rules {
      values {
        allowed_values = ["projects/${google_project.this.project_id}/zones/${var.vm_zone}/instances/${var.vm_name}"]
      }
    }
  }

  depends_on = [google_project_service.services]
}
