
data "cloudflare_ip_ranges" "whitelist" {

}

resource "cloudflare_dns_record" "www" {
  name = "www"

  content = hcloud_server.server.ipv4_address
  proxied = true
  ttl     = 1
  type    = "A"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "ssh" {
  name = "ssh"

  content = hcloud_server.server.ipv4_address
  proxied = false
  ttl     = 1
  type    = "A"
  zone_id = var.cloudflare_zone_id
}
