output "server_id" {
  value = hcloud_server.server.id
}

output "server_ip" {
  value = hcloud_server.server.ipv4_address
}


output "root_private_key" {
  value     = tls_private_key.root.private_key_pem
  sensitive = true
}
output "admin_private_key" {
  value     = tls_private_key.admin.private_key_openssh
  sensitive = true
}
