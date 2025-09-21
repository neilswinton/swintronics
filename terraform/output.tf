locals {
  infisical_client_id     = infisical_identity_universal_auth_client_secret.docker_deploy_client_secret.client_id
  infisical_client_secret = nonsensitive(infisical_identity_universal_auth_client_secret.docker_deploy_client_secret.client_secret)
}

output "server_ids" {
  value = hcloud_server.server[*].id
}

output "server_ip" {
  value = hcloud_server.server[*].ipv4_address
}


output "root_private_key" {
  value     = tls_private_key.root.private_key_pem
  sensitive = true
}
output "admin_private_key" {
  value     = tls_private_key.admin.private_key_openssh
  sensitive = true
}

# export INFISICAL_TOKEN=$(infisical login --method=universal-auth --client-id=<client-id> --client-secret=<client-secret> --silent --plain) # silent and plain is important to ensure only the token itself is printed, so we can easily set it as an environment variable.
output "docker_deploy_infisical_login" {
  value     = "export INFISICAL_TOKEN=$(infisical login --method=universal-auth --client-id=${local.infisical_client_id} --client-secret=${local.infisical_client_secret} --silent --plain)"
  sensitive = true
}
output "docker_deploy_infisical_project_id" {
  value = infisical_project.runtime_secrets.id
}
