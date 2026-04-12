variable "project_name" {
  default     = "swintronics"
  type        = string
  description = "The name of your server"
}

variable "region" {
  default     = "ash"
  type        = string
  description = "The cloud region where resources will be deployed."
}

variable "image" {
  default     = "ubuntu-24.04"
  type        = string
  description = "The image the server is created from."
}

variable "server_type" {
  type        = string
  default     = "CPX11"
  description = "Hetzner server type (e.g. CPX11, CPX21). Only used when cloud_provider = 'hetzner'."
}

variable "volume_size" {
  type        = number
  description = "The size in GiB of the volume which will be attached to the server"
}

variable "volume_delete_protection" {
  default     = false
  type        = bool
  description = "If set to true is going to protect volume from deletion."
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
  description = "The timezone which the server will be configured."
}


variable "infisical_client_id" {
  type        = string
  sensitive   = true
  default     = ""
  description = "The infisical client id."
}

variable "infisical_client_secret" {
  type        = string
  sensitive   = true
  default     = ""
  description = "The infisical client secret."
}

variable "infisical_project_id" {
  type        = string
  sensitive   = true
  default     = ""
  description = "The infisical project ID."
}

variable "infisical_api_url" {
  type        = string
  default     = "https://app.infisical.com"
  description = "The infisical api URL. This value will be exported to INFISICAL_API_URL if set"
}

variable "infisical_project_user_username" {
  description = "Username or email for Infisical project user"
  type        = string
  default     = "" # empty to skip inviting user -- unneeded for admins
}

variable "data_disk_mountpoint" {
  type        = string
  default     = "/mnt/docker-data"
  description = "Mountpoint for the data disk"
}

variable "domain_name" {
  type = string
  description = "The domain name of the server"
}