variable "project_name" {
  type        = string
  description = "Name used for all Hetzner resources."
}

variable "admin_public_key" {
  type        = string
  description = "Public key injected via cloud-init (admin user SSH access)."
}

variable "hcloud_public_key" {
  type        = string
  description = "Public key registered with Hetzner API (used for emergency console access)."
}

variable "user_data" {
  type        = string
  description = "Rendered cloud-init config."
}

variable "region" {
  type        = string
  default     = "ash"
  description = "Hetzner location code (ash, fsn1, nbg1, hel1, hil, sin)."
}

variable "server_type" {
  type        = string
  default     = "CPX11"
  description = "Hetzner server type."

  validation {
    condition     = contains(["CPX11", "CPX21", "CPX31", "CPX41", "CPX51"], var.server_type)
    error_message = "server_type must be one of: CPX11, CPX21, CPX31, CPX41, CPX51."
  }
}

variable "image" {
  type        = string
  default     = "ubuntu-24.04"
  description = "Hetzner OS image name."
}

variable "volume_size_gb" {
  type        = number
  description = "Size in GiB of the attached data volume."
}

variable "volume_delete_protection" {
  type        = bool
  default     = false
  description = "Prevent accidental volume deletion."
}

variable "my_ip" {
  type        = string
  description = "Caller public IP for SSH firewall rule (CIDR host address, without /32)."
}
