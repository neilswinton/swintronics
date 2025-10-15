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

variable "server_types" {
  type        = list(string)
  description = "A list of Hetzner server types to deploy."
  validation {
    condition     = length(var.server_types) > 0 && length(var.server_types) <= 8 && alltrue([for server_type in var.server_types : contains(local.hetzner_server_types, server_type)])
    error_message = "List must be 1-8 entries long.  Each entry must be one of:  ${join(", ", local.hetzner_server_types)}."
  }
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

variable "source_repo" {
  type        = string
  default     = "https://github.com/neilswinton/swintronics.git"
  description = "Repository to clone on cloud instance"
}