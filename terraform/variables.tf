variable "project_name" {
  type        = string
  description = "Name used for resources across all providers."
}

variable "admin_user" {
  type        = string
  description = "OS username to create on provisioned servers (used in cloud-init)."
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

variable "server_hostname" {
  type        = string
  default     = null
  description = "Hostname for the cloud server (e.g. 'oci-1'). Creates a DNS A record at <hostname>.<domain_name> pointing to the server's public IP. Null to skip."
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
    region              = optional(string, "us-ashburn-1")
    ocpus               = optional(number, 1)
    memory_in_gbs       = optional(number, 6)
    boot_volume_size_gb = optional(number, 50)
    data_volume_size_gb = optional(number, 60)
  })
  default     = {}
  description = "Oracle Cloud configuration. Defaults to a single A1.Flex instance within the free tier (200 GiB total block storage)."
}

# Backups (Backblaze B2 + restic)
variable "backup_bucket_name" {
  type        = string
  default     = ""
  description = "B2 bucket name for backups. Defaults to '<project_name>-restic'. Override to match an existing bucket when importing."
}

variable "restic_repository_path" {
  type        = string
  default     = ""
  description = "Path within the B2 bucket for the restic repository (no leading slash). Leave empty for bucket root. Set to e.g. 'backups/immich' to match an existing repo."
}

variable "b2_region" {
  type        = string
  default     = "us-east-005"
  description = "B2 cluster/region for the S3-compatible endpoint (e.g. us-east-005, us-west-002, eu-central-003). Must match the bucket's actual cluster — restic uses the S3 API because B2's native auth endpoint is unreliable across versions."
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
