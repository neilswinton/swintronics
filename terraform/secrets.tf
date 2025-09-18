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
