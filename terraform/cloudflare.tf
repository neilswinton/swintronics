
data "cloudflare_ip_ranges" "whitelist" {

}

resource "cloudflare_dns_record" "service_dns" {

  for_each = toset(var.services)
  name     = "${each.key}.${var.domain}"

  content = var.domain
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.cloudflare_zone_id

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
