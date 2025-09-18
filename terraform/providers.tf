# Tell terraform to use the provider and select a version.
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    infisical = {
      source  = "infisical/infisical"
      version = "~> 0.15"
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

