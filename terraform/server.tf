
locals {
  server_ip     = "10.10.1.8"
  userdata_path = "${path.module}/scripts/runcmd.sh"
  user_data = templatefile("${path.module}/scripts/cloud-init.yml", {
    admin_public_key = tls_private_key.admin.public_key_openssh
    admin_user       = var.admin_user
    timezone         = var.timezone
    custom_userdata = fileexists(local.userdata_path) ? split("\n", templatefile(local.userdata_path, {
      username = var.admin_user
      }
    )) : []
  })
}

resource "hcloud_server" "server" {

  count = var.cluster_size

  name         = "${var.name}-${count.index}"
  image        = var.image
  server_type  = lower(var.server_type)
  location     = var.region
  firewall_ids = [hcloud_firewall.cluster.id]
  ssh_keys     = [hcloud_ssh_key.server_public_key.name]

  user_data = local.user_data

  lifecycle {
    ignore_changes = [ssh_keys]
  }


  public_net {
    ipv6_enabled = true
    ipv4_enabled = true
  }
}

resource "hcloud_volume" "server_disk" {
  count             = var.cluster_size
  name              = "${var.name}-${count.index}-data"
  size              = var.volume_size
  location          = var.region
  automount         = false
  format            = "ext4"
  delete_protection = var.volume_delete_protection
}

resource "hcloud_volume_attachment" "server" {
  count = var.cluster_size

  volume_id = hcloud_volume.server_disk[count.index].id
  server_id = hcloud_server.server[count.index].id
  automount = false
}


resource "local_file" "cloudinit" {
  content         = local.user_data
  filename        = "${path.module}/artifacts/cloud-init.yml"
  file_permission = "0644"
}
