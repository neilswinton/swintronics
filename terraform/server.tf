
locals {
  deployr_version      = "0.2"
  network_ip_range     = "10.10.0.0/16"
  network_subnet_range = "10.10.1.0/24"
  server_ip            = "10.10.1.8"
}




resource "hcloud_network" "core-network" {
  name     = "network"
  ip_range = local.network_ip_range
}

resource "hcloud_network_subnet" "cluster-subnet" {
  type         = "cloud"
  network_id   = hcloud_network.core-network.id
  network_zone = (var.region == "ash") ? "us-east" : null
  ip_range     = local.network_subnet_range

  depends_on = [
    hcloud_network.core-network,
  ]
}

resource "hcloud_server_network" "cluster-network" {
  count = var.cluster_size

  server_id = hcloud_server.server[count.index].id
  subnet_id = hcloud_network_subnet.cluster-subnet.id
}

resource "hcloud_server" "server" {

  count = var.cluster_size

  name         = "${var.name}-${count.index}"
  image        = var.image
  server_type  = lower(var.server_type)
  location     = var.region
  firewall_ids = [hcloud_firewall.cluster.id]
  ssh_keys     = [hcloud_ssh_key.server_public_key.name]

  user_data = templatefile("${path.module}/scripts/cloud-init.yml", {
    admin_public_key = tls_private_key.admin.public_key_openssh
    admin_user       = var.admin_user
    timezone         = var.timezone
  })

  lifecycle {
    ignore_changes = [ssh_keys]
  }


  public_net {
    ipv6_enabled = false
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


