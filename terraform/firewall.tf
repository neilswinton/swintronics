locals {
  any_ip = ["0.0.0.0/0", "::/0"]
  my_ip  = chomp(data.http.myip.response_body)
}

data "http" "myip" {
  url = "https://ipv4.icanhazip.com"

  # Optional request headers
  request_headers = {
    Accept = "text/plain"
  }
}

# Allow any IP into ports 80 and 443.  Only allow my local IP into ssh

resource "hcloud_firewall" "cluster" {
  name = var.name

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["${local.my_ip}/32"]
  }
  # Ports blocked for tailscale

}
