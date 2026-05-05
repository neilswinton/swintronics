# Tell terraform to use the provider and select a version.
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.52"
    }
    infisical = {
      source  = "infisical/infisical"
      version = "~> 0.15"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.21"
    }
  }
}

provider "infisical" {
  host = "https://app.infisical.com" # Optional for cloud, required for self-hosted
  auth = {
    universal = { # or use oidc authentication method by providing an identity_id
      client_id     = var.infisical_client_id
      client_secret = var.infisical_client_secret
    }
  }
}

# Configure the Hetzner Cloud Provider
provider "hcloud" {
  # Dummy 64-char token when Hetzner isn't configured — the provider validates
  # token length at init even when no hcloud resources are being created.
  token = try(data.infisical_secrets.terraform_secrets.secrets["HETZNER_TOKEN"].value, "0000000000000000000000000000000000000000000000000000000000000000")
}

provider "oci" {
  tenancy_ocid = try(data.infisical_secrets.terraform_secrets.secrets["OCI_TENANCY_OCID"].value, "")
  user_ocid    = try(data.infisical_secrets.terraform_secrets.secrets["OCI_USER_OCID"].value, "")
  fingerprint  = try(data.infisical_secrets.terraform_secrets.secrets["OCI_FINGERPRINT"].value, "")
  private_key  = try(data.infisical_secrets.terraform_secrets.secrets["OCI_PRIVATE_KEY"].value, "")
  region       = try(data.infisical_secrets.terraform_secrets.secrets["OCI_REGION"].value, "")
}

# Provider for tailscale using provisioning client id

provider "tailscale" {
  oauth_client_id     = ephemeral.infisical_secret.tailscale_provider_oauth_client.value
  oauth_client_secret = ephemeral.infisical_secret.tailscale_provider_oauth_client_secret.value
}

# S3-compatible backend for Terraform state (Cloudflare R2 or Backblaze B2).
# See https://developers.cloudflare.com/terraform/advanced-topics/remote-backend for R2 requirements
#
# Deployment-specific values (bucket, key, endpoints) are in backend.hcl (gitignored).
# AWS credentials come from the environment: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY.
#
# Initialize with:
#   terraform init -backend-config=backend.hcl
#
terraform {
  backend "s3" {
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
