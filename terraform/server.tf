
locals {
  user_data = templatefile("${path.module}/scripts/cloud-init.yml", {
    admin_public_key = trimspace(tls_private_key.admin.public_key_openssh)
    admin_user       = nonsensitive(data.infisical_secrets.root_secrets.secrets["username"].value)
    timezone         = var.timezone
    mountpoint       = var.data_disk_mountpoint
  })
}


resource "hcloud_server" "server" {

  count        = min(var.cloud_provider == "hetzner" ? 1 : 0, length(var.server_types))
  name         = "${var.project_name}-${count.index}"
  image        = var.image
  server_type  = lower(var.server_types[0])
  location     = var.region
  firewall_ids = [hcloud_firewall.cluster[0].id]
  ssh_keys     = [hcloud_ssh_key.server_public_key[0].name]

  user_data = local.user_data

  lifecycle {
    ignore_changes = [ssh_keys, user_data]
  }


  public_net {
    ipv6_enabled = true
    ipv4_enabled = true
  }
}

resource "hcloud_volume" "server_disk" {
  count             = var.cloud_provider == "hetzner" ? 1 : 0
  name              = "${var.project_name}-${count.index}-data"
  size              = var.volume_size
  location          = var.region
  automount         = false
  delete_protection = var.volume_delete_protection
}

resource "hcloud_volume_attachment" "server" {
  count = var.cloud_provider == "hetzner" ? 1 : 0

  volume_id = hcloud_volume.server_disk[count.index].id
  server_id = hcloud_server.server[count.index].id
  automount = false
}


resource "local_file" "cloudinit" {
  content         = local.user_data
  filename        = "${path.module}/artifacts/cloud-init.yml"
  file_permission = "0644"
}

