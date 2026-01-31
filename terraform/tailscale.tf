# Create an identity for the tailscale docker container and save it to the secrets vault

locals {
  tailscale_server_tag = "tag:server"
}

resource "tailscale_tailnet_key" "swintronics_auth" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = [local.tailscale_server_tag]
  expiry        = 7776000 # 90 days
}

