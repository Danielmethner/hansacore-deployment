variable "ssh_public_key" {
  description = "OpenSSH public key line uploaded as the only login key (ssh-ed25519 AAAA...)."
  type        = string

  validation {
    condition     = startswith(var.ssh_public_key, "ssh-")
    error_message = "ssh_public_key must be an OpenSSH public key line."
  }
}

variable "ssh_allowed_cidrs" {
  description = "Source CIDRs allowed to open TCP 22. Includes IPv6 when SSH should work over it. Tighten this before any banking review."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]

  validation {
    condition     = length(var.ssh_allowed_cidrs) > 0
    error_message = "ssh_allowed_cidrs must contain at least one CIDR."
  }
}

variable "zone_name" {
  description = "Public DNS zone. Nameservers are delegated at the registrar after the first apply."
  type        = string
  default     = "hansacore.com"
}
