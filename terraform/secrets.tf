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
# Deterministic generated secrets.
#
# Each secret is derived from sha256("${project_name}-${secret_name}"):
#   - type = "hex":    substr of the 64-char hex digest (URL-safe, alphanumeric)
#   - type = "base64": base64 of the 32-byte raw digest (44 chars, for keys
#                      that expect binary entropy like encryption keys)
#
# Values can be pinned via var.password_overrides — useful during failover
# when services on a new cluster must keep passwords already in use.
locals {
  _password_specs = {
    IMMICH_DB_PASSWORD              = { type = "hex", length = 16 }
    PAPERLESS_SECRET_KEY            = { type = "hex", length = 50 }
    LINKWARDEN_NEXTAUTH_SECRET      = { type = "hex", length = 16 }
    LINKWARDEN_MEILI_MASTER_KEY     = { type = "hex", length = 16 }
    LINKWARDEN_POSTGRES_PASSWORD    = { type = "hex", length = 16 }
    DOCKHAND_ENCRYPTION_KEY         = { type = "base64" }
  }

  passwords = {
    for name, spec in local._password_specs :
    name => try(
      var.password_overrides[name],
      spec.type == "base64"
      ? base64sha256("${var.project_name}-${name}")
      : substr(sha256("${var.project_name}-${name}"), 0, spec.length)
    )
  }
}

# Immich
resource "infisical_secret" "immich_postgres_password" {
  name         = "IMMICH_DB_PASSWORD"
  value        = local.passwords["IMMICH_DB_PASSWORD"]
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

# Paperless
resource "infisical_secret" "paperless_secret_key" {
  name         = "PAPERLESS_SECRET_KEY"
  value        = local.passwords["PAPERLESS_SECRET_KEY"]
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

# Linkwarden
resource "infisical_secret" "linkwarden_passwords" {
  for_each     = toset(["NEXTAUTH_SECRET", "MEILI_MASTER_KEY", "POSTGRES_PASSWORD"])
  name         = "LINKWARDEN_${each.key}"
  value        = local.passwords["LINKWARDEN_${each.key}"]
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

# Dockhand
resource "infisical_secret" "dockhand_encryption_key" {
  name         = "DOCKHAND_ENCRYPTION_KEY"
  value        = local.passwords["DOCKHAND_ENCRYPTION_KEY"]
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}


