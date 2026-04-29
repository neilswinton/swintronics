locals {
  hetzner_server_types = ["CPX11", "CPX21", "CPX31", "CPX41", "CPX51"]

  hetzner_location_to_zone = transpose({
    "ap-southeast" = ["sin"],
    "eu-central"   = ["fsn1", "hel1", "nbg1"],
    "us-east"      = ["ash"],
    "us-west"      = ["hil"],
  })

  cluster_zone         = local.hetzner_location_to_zone[var.region][0]
  zone_ip_range        = module.subnet_addrs.network_cidr_blocks[local.cluster_zone]
  cluster_subnet_range = cidrsubnet(local.zone_ip_range, 8, 1)
}

module "subnet_addrs" {
  source = "hashicorp/subnets/cidr"

  base_cidr_block = "10.0.0.0/8"
  networks = [
    { name = "ap-southeast", new_bits = 8 },
    { name = "eu-central",   new_bits = 8 },
    { name = "us-east",      new_bits = 8 },
    { name = "us-west",      new_bits = 8 },
  ]
}

resource "hcloud_ssh_key" "server" {
  name       = "${var.project_name}-key"
  public_key = var.hcloud_public_key
}

resource "hcloud_firewall" "server" {
  name = var.project_name

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["${var.my_ip}/32"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "41641"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_network" "server" {
  name     = "${var.project_name}-network"
  ip_range = local.zone_ip_range
}

resource "hcloud_network_subnet" "server" {
  network_zone = local.cluster_zone
  type         = "cloud"
  network_id   = hcloud_network.server.id
  ip_range     = local.cluster_subnet_range

  depends_on = [hcloud_network.server]
}

resource "hcloud_server" "server" {
  name         = var.project_name
  image        = var.image
  server_type  = lower(var.server_type)
  location     = var.region
  firewall_ids = [hcloud_firewall.server.id]
  ssh_keys     = [hcloud_ssh_key.server.name]
  user_data    = var.user_data

  lifecycle {
    ignore_changes = [ssh_keys, user_data]
  }

  public_net {
    ipv6_enabled = true
    ipv4_enabled = true
  }
}

resource "hcloud_server_network" "server" {
  server_id = hcloud_server.server.id
  subnet_id = hcloud_network_subnet.server.id
}

resource "hcloud_volume" "server" {
  name              = "${var.project_name}-data"
  size              = var.volume_size_gb
  location          = var.region
  automount         = false
  delete_protection = var.volume_delete_protection
}

resource "hcloud_volume_attachment" "server" {
  volume_id = hcloud_volume.server.id
  server_id = hcloud_server.server.id
  automount = false
}
