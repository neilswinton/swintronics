ephemeral "infisical_secret" "cloudflare_api_token" {
  name         = "CLOUDFLARE_API_TOKEN"
  env_slug     = "dev"
  workspace_id = var.infisical_project_id
  folder_path  = "/terraform"
}


provider "cloudflare" {
  api_token = ephemeral.infisical_secret.cloudflare_api_token.value
}



data "cloudflare_ip_ranges" "whitelist" {

}

resource "cloudflare_dns_record" "ssh" {
  name = "ssh.${var.domain}"

  content = hcloud_server.server[0].ipv4_address
  proxied = false
  ttl     = 1
  type    = "A"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "root" {
  name = "@"

  content = hcloud_server.server[0].ipv4_address
  proxied = false
  ttl     = 1
  type    = "A"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "webservices" {
  name = "*.ts"

  content = hcloud_server.server[0].ipv4_address
  proxied = false
  ttl     = 1
  type    = "A"
  zone_id = var.cloudflare_zone_id
}
