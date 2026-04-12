variable "project_name" {
  type        = string
  description = "Name used for all OCI resources."
}

variable "admin_public_key" {
  type        = string
  description = "Public key injected via cloud-init (admin user SSH access)."
}

variable "user_data" {
  type        = string
  description = "Rendered cloud-init config."
}

variable "compartment_ocid" {
  type        = string
  sensitive   = true
  description = "OCI compartment OCID. For simple deployments this is the tenancy OCID."
}

variable "region" {
  type        = string
  default     = "us-ashburn-1"
  description = "OCI region identifier."
}

variable "ocpus" {
  type        = number
  default     = 1
  description = "Number of OCPUs for the A1.Flex instance (free tier: up to 4 total)."
}

variable "memory_in_gbs" {
  type        = number
  default     = 6
  description = "Memory in GiB for the A1.Flex instance (free tier: up to 24 GiB total)."
}

variable "my_ip" {
  type        = string
  description = "Caller public IP for SSH security list rule (without /32)."
}
