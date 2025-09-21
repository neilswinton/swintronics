resource "tls_private_key" "root" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "local_file" "server_private_key" {
  content         = tls_private_key.root.private_key_openssh
  filename        = "${path.module}/artifacts/${var.project_name}_root_ecdsa"
  file_permission = "0600"
}
resource "local_file" "server_public_key" {
  content         = tls_private_key.root.public_key_openssh
  filename        = "${path.module}/artifacts/${var.project_name}_root_ecdsa.pub"
  file_permission = "0644"
}

resource "hcloud_ssh_key" "server_public_key" {
  name       = "${var.project_name}-key"
  public_key = tls_private_key.root.public_key_openssh
}

resource "tls_private_key" "admin" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "local_file" "admin_private_key" {
  content         = tls_private_key.admin.private_key_openssh
  filename        = "${path.module}/artifacts/${var.project_name}_admin_ecdsa"
  file_permission = "0600"
}
resource "local_file" "admin_public_key" {
  content         = tls_private_key.admin.public_key_openssh
  filename        = "${path.module}/artifacts/${var.project_name}_admin_ecdsa.pub"
  file_permission = "0644"
}
