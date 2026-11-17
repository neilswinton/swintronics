provider "cloudflare" {
  api_token = try(data.infisical_secrets.root_secrets.secrets["CF_DNS_API_TOKEN"].value, "")
}

# Public DNS record for the cloud server: <server_hostname>.<domain> → public IP.
# Public services on that host CNAME to this name (dns_cname_target in the
# host's Ansible vars). Tailnet-side records (<dns_hostname>, per-service
# CNAMEs) are managed by Ansible (dns.yml, deploy-versions.yml).
#
# There is deliberately no apex (@) or wildcard (*) record here: the apex would
# be repointed at whichever cloud server is active, and a wildcard would make
# every unclaimed name resolve to a server.
data "cloudflare_zone" "main" {
  filter = {
    name = var.domain_name
  }
}

resource "cloudflare_dns_record" "host" {
  count   = var.server_hostname != null && var.cloud_provider != null ? 1 : 0
  name    = var.server_hostname
  content = local.server_ip
  proxied = false
  ttl     = 1
  type    = "A"
  zone_id = data.cloudflare_zone.main.zone_id
  comment = "Deployed ${timestamp()} host ${var.server_hostname} for ${var.project_name}"
  lifecycle {
    ignore_changes = [comment]
  }
}
