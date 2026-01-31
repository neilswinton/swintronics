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
  token = ephemeral.infisical_secret.hetzner_token.value
}

# Provider for tailscale using provisioning client id

provider "tailscale" {
  oauth_client_id     = ephemeral.infisical_secret.tailscale_provider_oauth_client.value
  oauth_client_secret = ephemeral.infisical_secret.tailscale_provider_oauth_client_secret.value
}

# Configure the R2 backend for terraform state storage
terraform {
  backend "s3" {
    bucket = "swintronics-tfstate"
    key    = "swintronics/terraform.tfstate"
    region = "auto"
    endpoints = {
      s3 = "https://b36f9e73188dcaad461bb82e5ff002f7.r2.cloudflarestorage.com"
    }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
