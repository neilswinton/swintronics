data "http" "myip" {
  url = "https://ipv4.icanhazip.com"
  request_headers = {
    Accept = "text/plain"
  }
}

locals {
  my_ip            = chomp(data.http.myip.response_body)
  admin_public_key = trimspace(tls_private_key.admin.public_key_openssh)
  admin_user       = var.admin_user

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
  region                   = var.hetzner.region
  server_type              = var.hetzner.server_type
  image                    = var.hetzner.image
  volume_size_gb           = var.hetzner.volume_size_gb
  volume_delete_protection = var.hetzner.volume_delete_protection
  my_ip                    = local.my_ip
}

module "oci" {
  count  = var.cloud_provider == "oci" ? 1 : 0
  source = "./modules/oci"

  project_name        = var.project_name
  admin_public_key    = local.admin_public_key
  user_data           = local.user_data
  region              = var.oci.region
  ocpus               = var.oci.ocpus
  memory_in_gbs       = var.oci.memory_in_gbs
  boot_volume_size_gb = var.oci.boot_volume_size_gb
  data_volume_size_gb = var.oci.data_volume_size_gb
  compartment_ocid = coalesce(
    try(data.infisical_secrets.terraform_secrets.secrets["OCI_COMPARTMENT_OCID"].value, ""),
    try(data.infisical_secrets.terraform_secrets.secrets["OCI_TENANCY_OCID"].value, ""),
  )
  my_ip = local.my_ip
}

resource "local_file" "cloudinit" {
  content         = local.user_data
  filename        = "${path.module}/artifacts/cloud-init.yml"
  file_permission = "0644"
}
