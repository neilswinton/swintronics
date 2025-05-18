


resource "cloudflare_dns_record" "www" {
  name = "www"

  content = hcloud_server.server.ipv4_address
  proxied = true
  ttl     = 1
  type    = "A"
  zone_id = var.cloudflare_zone_id
}
