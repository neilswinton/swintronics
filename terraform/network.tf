locals {
  cluster_zone         = local.hetzner_location_to_zone[var.region][0]
  zone_ip_range        = module.subnet_addrs.network_cidr_blocks[local.cluster_zone]
  cluster_subnet_range = cidrsubnet(local.zone_ip_range, 8, 1)
}

resource "hcloud_network" "zone-network" {
  name     = "zone-network"
  ip_range = local.zone_ip_range
}

resource "hcloud_network_subnet" "cluster-subnet" {
  network_zone = local.cluster_zone
  type         = "cloud"
  network_id   = hcloud_network.zone-network.id
  ip_range     = local.cluster_subnet_range

  depends_on = [
    hcloud_network.zone-network,
  ]

}

resource "hcloud_server_network" "server-subnet-binding" {
  count = var.cluster_size

  server_id = hcloud_server.server[count.index].id
  subnet_id = hcloud_network_subnet.cluster-subnet.id
}
