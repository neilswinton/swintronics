
provider "cloudflare" {
  api_token = ephemeral.infisical_secret.cloudflare_api_token.value
}

resource "cloudflare_dns_record" "root" {
  count   = local.server_ip != null ? 1 : 0
  name    = "@"
  content = local.server_ip
  proxied = false
  ttl     = 1
  type    = "A"
  zone_id = data.infisical_secrets.terraform_secrets.secrets["CLOUDFLARE_ZONE_ID"].value
  comment = "Deployed ${timestamp()} root for ${var.project_name}"
  lifecycle {
    ignore_changes = [comment]
  }
}

# Get Tailscale devices matching the project name for wildcard DNS
data "tailscale_devices" "container" {
  name_prefix = var.project_name
}

locals {
  container_devices = {
    for device in data.tailscale_devices.container.devices :
    device.name => (
      try(
        [for addr in device.addresses : addr if can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", addr))][0],
        null
      )
    )
  }
}

# Wildcard DNS record pointing at the server's Tailscale IP
resource "cloudflare_dns_record" "webservices" {
  name     = "*"
  for_each = local.container_devices

  content = each.value
  proxied = false
  ttl     = 1
  type    = "A"
  zone_id = data.infisical_secrets.terraform_secrets.secrets["CLOUDFLARE_ZONE_ID"].value
  comment = "Deployed ${timestamp()} webservices wildcard for ${var.project_name}"
  lifecycle {
    ignore_changes = [comment]
  }
}
