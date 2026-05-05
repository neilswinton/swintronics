# Secrets from key vault (currently Infisical)

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
  workspace_id = var.infisical_project_id
  folder_path  = "/terraform"
}

ephemeral "infisical_secret" "tailscale_provider_oauth_client_secret" {
  name         = "TS_MS_PROVIDER_OAUTH_CLIENT_SECRET"
  env_slug     = "dev"
  workspace_id = var.infisical_project_id
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
  value        = tailscale_tailnet_key.primary.key
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

resource "infisical_secret" "tailscale_failover_auth_key" {
  name         = "TS_FAILOVER_AUTH_KEY"
  value        = tailscale_tailnet_key.failover.key
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
# Generated secrets — random_password keeps values stable in Terraform state.
# To preserve an existing value on a re-pave or new cluster, import before applying:
#   terraform import random_password.<name> "<value>"

resource "random_password" "immich_db_password" {
  length      = 16
  special     = true
  min_special = 0
}

resource "random_password" "paperless_secret_key" {
  length      = 50
  special     = true
  min_special = 0
}

resource "random_password" "dockhand_encryption_key" {
  length      = 44
  special     = true
  min_special = 0
}

resource "random_password" "z2m_frontend_auth_token" {
  length  = 32
  special = false
}

# Immich
resource "infisical_secret" "immich_postgres_password" {
  name         = "IMMICH_DB_PASSWORD"
  value        = random_password.immich_db_password.result
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

# Paperless
resource "infisical_secret" "paperless_secret_key" {
  name         = "PAPERLESS_SECRET_KEY"
  value        = random_password.paperless_secret_key.result
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

# Dockhand
resource "infisical_secret" "dockhand_encryption_key" {
  name         = "DOCKHAND_ENCRYPTION_KEY"
  value        = random_password.dockhand_encryption_key.result
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

# Zigbee2MQTT
resource "infisical_secret" "z2m_frontend_auth_token" {
  name         = "Z2M_FRONTEND_AUTH_TOKEN"
  value        = random_password.z2m_frontend_auth_token.result
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}


