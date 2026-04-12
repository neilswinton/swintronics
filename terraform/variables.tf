variable "project_name" {
  type        = string
  default     = "swintronics"
  description = "Name used for resources across all providers."
}

variable "cloud_provider" {
  type        = string
  default     = null
  description = "Cloud provider to provision: 'hetzner', 'oci', or null for local-only."
  validation {
    condition     = var.cloud_provider == null || contains(["hetzner", "oci"], var.cloud_provider)
    error_message = "cloud_provider must be null, 'hetzner', or 'oci'."
  }
}

variable "timezone" {
  type        = string
  description = "Timezone to configure on the server (e.g. America/New_York)."
}

variable "domain_name" {
  type        = string
  description = "Domain name for this deployment."
}

variable "data_disk_mountpoint" {
  type        = string
  default     = "/docker-data"
  description = "Mountpoint for the data disk (used in cloud-init)."
}

# Hetzner-specific configuration — only used when cloud_provider = "hetzner"
variable "hetzner" {
  type = object({
    region                   = optional(string, "ash")
    server_type              = optional(string, "CPX11")
    image                    = optional(string, "ubuntu-24.04")
    volume_size_gb           = optional(number, 40)
    volume_delete_protection = optional(bool, false)
  })
  default     = {}
  description = "Hetzner Cloud configuration. All fields have defaults suitable for a basic deployment."
}

# OCI-specific configuration — only used when cloud_provider = "oci"
variable "oci" {
  type = object({
    region        = optional(string, "us-ashburn-1")
    ocpus         = optional(number, 1)
    memory_in_gbs = optional(number, 6)
  })
  default     = {}
  description = "Oracle Cloud configuration. Defaults to a single A1.Flex instance within the free tier."
}

# Infisical
variable "infisical_client_id" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Infisical Machine Identity client ID."
}

variable "infisical_client_secret" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Infisical Machine Identity client secret."
}

variable "infisical_project_id" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Infisical source project ID."
}

variable "infisical_api_url" {
  type        = string
  default     = "https://app.infisical.com"
  description = "Infisical API URL. Override for self-hosted installations."
}

variable "infisical_project_user_username" {
  type        = string
  default     = ""
  description = "Username or email to invite to the runtime Infisical project. Leave empty to skip."
}
