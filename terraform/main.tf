data "http" "myip" {
  url = "https://ipv4.icanhazip.com"
  request_headers = {
    Accept = "text/plain"
  }
}

locals {
  my_ip            = chomp(data.http.myip.response_body)
  admin_public_key = trimspace(tls_private_key.admin.public_key_openssh)
  admin_user       = nonsensitive(data.infisical_secrets.root_secrets.secrets["username"].value)

  user_data = templatefile("${path.module}/scripts/cloud-init.yml", {
    admin_public_key = local.admin_public_key
    admin_user       = local.admin_user
    timezone         = var.timezone
    mountpoint       = var.data_disk_mountpoint
  })

  # Resolved server IP regardless of which cloud provider is active
  server_ip = try(
    coalesce(
      try(module.hetzner[0].server_ip, null),
      try(module.oci[0].server_ip, null),
    ),
    null
  )
}

module "hetzner" {
  count  = var.cloud_provider == "hetzner" ? 1 : 0
  source = "./modules/hetzner"

  project_name             = var.project_name
  admin_public_key         = local.admin_public_key
  hcloud_public_key        = trimspace(tls_private_key.root.public_key_openssh)
  user_data                = local.user_data
  region                   = var.region
  server_type              = var.server_type
  image                    = var.image
  volume_size_gb           = var.volume_size
  volume_delete_protection = var.volume_delete_protection
  my_ip                    = local.my_ip
}

module "oci" {
  count  = var.cloud_provider == "oci" ? 1 : 0
  source = "./modules/oci"

  project_name     = var.project_name
  admin_public_key = local.admin_public_key
  user_data        = local.user_data
  region           = var.region
  compartment_ocid = coalesce(
    try(data.infisical_secrets.root_secrets.secrets["OCI_COMPARTMENT_OCID"].value, ""),
    try(data.infisical_secrets.root_secrets.secrets["OCI_TENANCY_OCID"].value, ""),
  )
  my_ip = local.my_ip
}

resource "local_file" "cloudinit" {
  content         = local.user_data
  filename        = "${path.module}/artifacts/cloud-init.yml"
  file_permission = "0644"
}
