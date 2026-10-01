# Disposable layer for SIT: network, VM, disks, IAM and DNS.
# `terraform destroy` here removes the whole environment (including the
# Postgres data disk); the project in infra/projects/sit stays.

module "environment" {
  source = "../../modules/environment"

  env         = "sit"
  project_id  = var.project_id
  subnet_cidr = "10.10.0.0/24"

  # Must match k8s/overlays/sit/hansacore-env.properties.
  hostnames = [
    "sit.hansacore.com",
    "sit.erp.hansacore.com",
    "sit.auth.hansacore.com",
  ]

  ssh_members = var.ssh_members
}
