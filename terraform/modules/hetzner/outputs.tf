output "server_ip" {
  value       = hcloud_server.server.ipv4_address
  description = "Public IPv4 address of the Hetzner server."
}

output "server_name" {
  value       = hcloud_server.server.name
  description = "Name of the Hetzner server."
}
