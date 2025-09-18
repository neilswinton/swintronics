
provider "cloudflare" {
  api_token = ephemeral.infisical_secret.cloudflare_api_token.value
}



data "cloudflare_ip_ranges" "whitelist" {

}

resource "cloudflare_dns_record" "ssh" {
  name = "ssh"

  content = hcloud_server.server[0].ipv4_address
  proxied = false
  ttl     = 1
  type    = "A"
  zone_id = data.infisical_secrets.terraform_secrets.secrets["CLOUDFLARE_ZONE_ID"].value
  comment = "Deployed ${timestamp()} ssh for ${var.name}"
}

resource "cloudflare_dns_record" "root" {
  name = "@"

  content = hcloud_server.server[0].ipv4_address
  proxied = false
  ttl     = 1
  type    = "A"
  zone_id = data.infisical_secrets.terraform_secrets.secrets["CLOUDFLARE_ZONE_ID"].value
  comment = "Deployed ${timestamp()} root for ${var.name}"
}

resource "cloudflare_dns_record" "webservices" {
  name = "*.ts"

  content = hcloud_server.server[0].ipv4_address
  proxied = false
  ttl     = 1
  type    = "A"
  zone_id = data.infisical_secrets.terraform_secrets.secrets["CLOUDFLARE_ZONE_ID"].value
  comment = "Deployed ${timestamp()} webservices wildcard for ${var.name}"
}
