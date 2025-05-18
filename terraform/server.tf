
locals {
  deployr_version      = "0.2"
  network_ip_range     = "10.10.1.0/16"
  network_subnet_range = "10.10.1.0/24"
  server_ip            = "10.10.1.5"
}




resource "hcloud_network" "network" {
  name     = "network"
  ip_range = local.network_ip_range
}

resource "hcloud_network_subnet" "network-subnet" {
  type         = "cloud"
  network_id   = hcloud_network.network.id
  network_zone = (var.region == "ash") ? "us-east" : null
  ip_range     = local.network_subnet_range
}

resource "hcloud_server" "server" {

  name         = var.name
  image        = var.image
  server_type  = lower(var.server_type)
  location     = var.region
  firewall_ids = [hcloud_firewall.cluster.id]
  ssh_keys     = [hcloud_ssh_key.server_public_key.name]

  user_data = templatefile("${path.module}/scripts/cloud-init.yml", { timezone = var.timezone })

  lifecycle {
    replace_triggered_by = [
      hcloud_volume.server_disk.size
    ]
    ignore_changes = [ssh_keys]
  }

  depends_on = [hcloud_network_subnet.network-subnet]

  network {
    network_id = hcloud_network.network.id
    ip         = local.server_ip
  }

  public_net {
    ipv6_enabled = false
    ipv4_enabled = true
  }
}

resource "hcloud_volume" "server_disk" {
  name              = "${var.name}-data"
  size              = var.volume_size
  location          = var.region
  automount         = false
  format            = "ext4"
  delete_protection = var.volume_delete_protection
}

resource "hcloud_volume_attachment" "server" {
  volume_id = hcloud_volume.server_disk.id
  server_id = hcloud_server.server.id
  automount = false
}


