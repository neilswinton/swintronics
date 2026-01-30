# Create an identity for the tailscale docker container and save it to the secrets vault

locals {
  tailscale_container_tag = "tag:container"
  tailscale_server_tag    = "tag:server"
}

resource "tailscale_oauth_client" "docker_identity" {
  description = "Docker OAuth client for ${var.project_name}"
  scopes      = ["devices:core", "auth_keys"]
  tags        = [local.tailscale_container_tag]
}

resource "tailscale_tailnet_key" "swintronics_auth" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = [local.tailscale_server_tag]
  expiry        = 7776000 # 90 days
}

