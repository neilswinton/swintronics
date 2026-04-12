locals {
  infisical_client_id     = infisical_identity_universal_auth_client_secret.docker_deploy_client_secret.client_id
  infisical_client_secret = nonsensitive(infisical_identity_universal_auth_client_secret.docker_deploy_client_secret.client_secret)
}

output "server_ip" {
  value       = local.server_ip
  description = "Public IP of the provisioned server (null if no cloud provider active)."
}

output "server_name" {
  value = try(
    coalesce(
      try(module.hetzner[0].server_name, null),
      try(module.oci[0].server_name, null),
    ),
    null
  )
}

output "root_private_key" {
  value     = tls_private_key.root.private_key_pem
  sensitive = true
}

output "admin_private_key" {
  value     = tls_private_key.admin.private_key_openssh
  sensitive = true
}

output "docker_deploy_infisical_login" {
  value     = " export INFISICAL_TOKEN=$(infisical login --method=universal-auth --client-id=${local.infisical_client_id} --client-secret=${local.infisical_client_secret} --silent --plain)"
  sensitive = true
}

output "docker_deploy_infisical_project_id" {
  value = " export INFISICAL_PROJECT_ID=${infisical_project.runtime_secrets.id}"
}
