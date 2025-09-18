# Create an identity for the tailscale docker container and save it to the secrets vault

locals {
  tailscale_container_tag = "container"
}
resource "tailscale_oauth_client" "docker_identity" {
  description = "Docker OAuth client for ${var.name}"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:${local.tailscale_container_tag}"]
}
