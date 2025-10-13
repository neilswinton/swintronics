
provider "cloudflare" {
  api_token = ephemeral.infisical_secret.cloudflare_api_token.value
}

data "cloudflare_ip_ranges" "whitelist" {

}

resource "cloudflare_dns_record" "ssh" {
  name    = "ssh"
  count   = 0
  content = hcloud_server.server[0].ipv4_address
  proxied = false
  ttl     = 1
  type    = "A"
  zone_id = data.infisical_secrets.terraform_secrets.secrets["CLOUDFLARE_ZONE_ID"].value
  comment = "Deployed ${timestamp()} ssh for ${var.project_name}"
  lifecycle {
    ignore_changes = [
      comment
    ]
  }
}

resource "cloudflare_dns_record" "root" {
  name = "@"

  content = hcloud_server.server[0].ipv4_address
  proxied = false
  ttl     = 1
  type    = "A"
  zone_id = data.infisical_secrets.terraform_secrets.secrets["CLOUDFLARE_ZONE_ID"].value
  comment = "Deployed ${timestamp()} root for ${var.project_name}"
  lifecycle {
    ignore_changes = [
      comment
    ]
  }
}

# Get the tailscale devices that could be our docker container
data "tailscale_devices" "container" {
  name_prefix = var.project_name
}

# Get the IPv4 address for the matching containers -- there should be just one
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

# Register a wildcard DNS record for the tailscale container's IP
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
    ignore_changes = [
      comment
    ]
  }

}
