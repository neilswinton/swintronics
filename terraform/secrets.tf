# Secrets from key vault (currently Infisical)

locals {
  infisical_project_slug = "swintronics-kwhf"
}
# 
data "infisical_projects" "server" {
  slug = local.infisical_project_slug
}

data "infisical_identity_details" "details" {
}


# Create a project for runtime secrets
resource "infisical_project" "runtime_secrets" {
  name = "${title(var.project_name)} Runtime"
  slug = "${var.project_name}-runtime"
}

# Give ourselves access
resource "infisical_project_user" "terraform" {
  count      = var.infisical_project_user_username != "" ? 1 : 0
  project_id = infisical_project.runtime_secrets.id
  username   = var.infisical_project_user_username
  roles = [
    {
      role_slug = "admin"
    }
  ]
}


ephemeral "infisical_secret" "tailscale_provider_oauth_client" {
  # OAuth client required scopes: auth_keys, devices:core, dns:read, oauth_keys
  # The "container" tag must exist and be assigned to the devices:core scope
  name         = "TS_MS_PROVIDER_OAUTH_CLIENT_ID"
  env_slug     = "dev"
  workspace_id = data.infisical_projects.server.id
  folder_path  = "/terraform"
}

ephemeral "infisical_secret" "tailscale_provider_oauth_client_secret" {
  name         = "TS_MS_PROVIDER_OAUTH_CLIENT_SECRET"
  env_slug     = "dev"
  workspace_id = data.infisical_projects.server.id
  folder_path  = "/terraform"
}

# Generate credentials for infisical login on server for docker
resource "infisical_identity" "docker_deploy" {
  name = "docker_deploy"
  role = "admin"
  # org_id = data.infisical_identity_details.server.organization.id
  org_id = data.infisical_identity_details.details.organization.id
}

resource "infisical_identity_universal_auth" "docker_deploy" {
  identity_id                 = infisical_identity.docker_deploy.id
  access_token_ttl            = 2592000
  access_token_max_ttl        = 2592000 * 2
  access_token_num_uses_limit = 3
}

resource "infisical_identity_universal_auth_client_secret" "docker_deploy_client_secret" {
  identity_id = infisical_identity.docker_deploy.id

  depends_on = [infisical_identity_universal_auth.docker_deploy]
}

resource "infisical_project_identity" "docker_deploy" {
  project_id  = infisical_project.runtime_secrets.id
  identity_id = infisical_identity.docker_deploy.id
  roles = [
    {
      role_slug = "viewer"
    }
  ]
}

# Populate runtime secrets to the runtime project
# Store tailscale-generated OAuth client credentials into Infisical

resource "infisical_secret" "tailscale_auth_key" {
  name         = "TS_AUTH_KEY"
  value        = tailscale_tailnet_key.swintronics_auth.key
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}
resource "infisical_secret" "cloudflare_runtime" {
  for_each     = toset(["CF_API_EMAIL", "CF_DNS_API_TOKEN"])
  name         = each.key
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
  value        = data.infisical_secrets.root_secrets.secrets[each.key].value
}


# Cloudflare secrets

ephemeral "infisical_secret" "cloudflare_api_token" {
  name         = "CLOUDFLARE_API_TOKEN"
  env_slug     = "dev"
  workspace_id = data.infisical_projects.server.id
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

data "infisical_secrets" "server_secrets" {
  env_slug     = "dev"
  workspace_id = var.infisical_project_id
  folder_path  = "/server"
}

# Telegram for sending notifications from the server

resource "infisical_secret" "server_secrets" {
  for_each     = data.infisical_secrets.server_secrets.secrets
  name         = each.key
  value        = each.value.value
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}
# Immich

resource "random_password" "immich_postgres_password" {
  length  = 16
  special = false
}


resource "infisical_secret" "immich_postgres_password" {
  name         = "IMMICH_DB_PASSWORD"
  value        = random_password.immich_postgres_password.result
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

# linkwarden
resource "random_password" "linkwarden_passwords" {
  for_each = toset(["NEXTAUTH_SECRET", "MEILI_MASTER_KEY", "POSTGRES_PASSWORD"])
  length   = 16
}

resource "infisical_secret" "linkwarden_passwords" {
  for_each     = random_password.linkwarden_passwords
  name         = "LINKWARDEN_${each.key}"
  value        = each.value.result
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

# Monitoring
resource "random_password" "monitoring_passwords" {
  for_each = toset(["GRAFANA_ADMIN_PASSWORD"])
  length   = 16
}

resource "infisical_secret" "monitoring_passwords" {
  for_each     = random_password.monitoring_passwords
  name         = "${each.key}"
  value        = each.value.result
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

resource "infisical_secret" "server_admin_username" {
  name         = "SERVER_ADMIN_USERNAME"
  value        = data.infisical_secrets.root_secrets.secrets["username"].value
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}
