
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
  firewall_ids = var.public_access ? [] : [hcloud_firewall.cluster[0].id]
  ssh_keys     = [hcloud_ssh_key.server_public_key.name]

  /* user_data = templatefile("${path.module}/scripts/bootstrap.sh", {
    tailscale_auth_key      = var.tailscale_auth_key
    linux_device            = hcloud_volume.server_disk.linux_device
    tailscale_routes        = var.tailscale_routes
    timezone                = var.timezone
    apps_repository_url     = format("https://%s@%s", var.github_token, replace(var.github_repo_url, "https://", ""))
    docker_compose_path     = var.docker_compose_path
    infisical_client_id     = var.infisical_client_id
    infisical_client_secret = var.infisical_client_secret
    infisical_project_id    = var.infisical_project_id
    infisical_api_url       = var.infisical_api_url
    custom_userdata         = var.custom_userdata
    deployr_version         = local.deployr_version
  }) */

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


