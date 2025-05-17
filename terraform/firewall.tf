resource "hcloud_firewall" "cluster" {
  count = var.public_access ? 0 : 1

  name = var.name
}
