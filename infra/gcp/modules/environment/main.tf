locals {
  prefix = "hansacore-${var.env}"

  # Network tag that the firewall rules target.
  web_tag = "${local.prefix}-web"

  # "uat.erp.hansacore.com" -> "uat-erp": the per-hostname label inside the
  # ACME zone that the _acme-challenge CNAME points to.
  acme_labels = {
    for h in var.hostnames : h => replace(trimsuffix(h, ".${var.domain}"), ".", "-")
  }
}
