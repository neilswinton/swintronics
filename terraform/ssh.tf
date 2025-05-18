resource "tls_private_key" "server" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}


resource "local_file" "server_private_key" {
  content         = tls_private_key.server.private_key_openssh
  filename        = "${path.module}/artifacts/${var.name}_ecdsa"
  file_permission = "0600"
}
resource "local_file" "server_public_key" {
  content         = tls_private_key.server.public_key_openssh
  filename        = "${path.module}/artifacts/${var.name}_ecdsa.pub"
  file_permission = "0644"
}

resource "hcloud_ssh_key" "server_public_key" {
  name       = "${var.name}-key"
  public_key = tls_private_key.server.public_key_openssh
}
