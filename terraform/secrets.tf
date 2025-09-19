# Secrets from key vault (currently Infisical)

# Cloudflare secrets

ephemeral "infisical_secret" "cloudflare_api_token" {
  name         = "CLOUDFLARE_API_TOKEN"
  env_slug     = "dev"
  workspace_id = var.infisical_project_id
  folder_path  = "/terraform"
}

ephemeral "infisical_secret" "cloudflare_zone_id" {
  name         = "CLOUDFLARE_ZONE_ID"
  env_slug     = "dev"
  workspace_id = var.infisical_project_id
  folder_path  = "/terraform"
}

# Hetzner 

ephemeral "infisical_secret" "hetzner_token" {
  name         = "HETZNER_TOKEN"
  env_slug     = "dev"
  workspace_id = var.infisical_project_id
  folder_path  = "/terraform"
}

data "infisical_secrets" "root_secrets" {
  env_slug     = "dev"
  workspace_id = var.infisical_project_id
  folder_path  = "/"
}

data "infisical_secrets" "terraform_secrets" {
  env_slug     = "dev"
  workspace_id = var.infisical_project_id
  folder_path  = "/terraform"
}

# Tailscale api key for provisioning in terraform
ephemeral "infisical_secret" "tailscale_api_key" {
  name         = "TS_API_KEY"
  env_slug     = "dev"
  workspace_id = var.infisical_project_id
  folder_path  = "/terraform"
}

# Store tailscale-generated OAuth client credentials into Infisical

resource "infisical_secret" "ts_docker_client_id" {
  name         = "TS_OAUTH_CLIENT_ID"
  value        = tailscale_oauth_client.docker_identity.id
  env_slug     = "dev"
  workspace_id = var.infisical_project_id
  folder_path  = "/server"
}
resource "infisical_secret" "ts_docker_client_secret" {
  name         = "TS_OAUTH_CLIENT_SECRET"
  value        = tailscale_oauth_client.docker_identity.key
  env_slug     = "dev"
  workspace_id = var.infisical_project_id
  folder_path  = "/server"
}
