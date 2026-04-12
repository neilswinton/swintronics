output "server_ip" {
  value       = oci_core_instance.server.public_ip
  description = "Public IPv4 address of the OCI instance."
}

output "server_name" {
  value       = oci_core_instance.server.display_name
  description = "Display name of the OCI instance."
}
