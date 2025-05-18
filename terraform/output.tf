output "server_id" {
  value = hcloud_server.server.id
}

output "server_ip" {
  value = hcloud_server.server.ipv4_address
}


output "private_key" {
  value     = tls_private_key.server.private_key_pem
  sensitive = true
}
