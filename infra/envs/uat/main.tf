# Disposable layer for UAT: network, VM, disks, IAM and DNS.
# `terraform destroy` here removes the whole environment (including the
# Postgres data disk); the project in infra/projects/uat stays.

module "environment" {
  source = "../../modules/environment"

  env         = "uat"
  project_id  = var.project_id
  subnet_cidr = "10.20.0.0/24"

  # Must match k8s/overlays/uat/hansacore-env.properties.
  hostnames = [
    "uat.hansacore.com",
    "uat.erp.hansacore.com",
    "uat.auth.hansacore.com",
  ]

  ssh_members = var.ssh_members
}
