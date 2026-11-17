# Create an identity for the tailscale docker container and save it to the secrets vault

locals {
  tailscale_server_tag = "tag:server"
  tailscale_public_tag = "tag:public"
}

resource "tailscale_tailnet_key" "primary" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = [local.tailscale_server_tag]
  expiry        = 7776000 # 90 days
}

resource "tailscale_tailnet_key" "failover" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = [local.tailscale_server_tag]
  expiry        = 7776000 # 90 days
}

# Auth key for hosts that serve public traffic. They join the tailnet for
# management only, under their own tag so the tailnet ACL can stop a
# compromised public host from reaching the rest of the tailnet.
# `tag:public` must exist in the tailnet policy's tagOwners and be owned by the
# tag of the OAuth client Terraform uses.
resource "tailscale_tailnet_key" "public" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = [local.tailscale_public_tag]
  expiry        = 7776000 # 90 days
}
