data "http" "myip" {
  url = "https://ipv4.icanhazip.com"

  # Optional request headers
  request_headers = {
    Accept = "text/plain"
  }
}


resource "hcloud_firewall" "cluster" {
  name = var.name

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["${chomp(data.http.myip.response_body)}/32"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["${chomp(data.http.myip.response_body)}/32"]
  }
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = ["0.0.0.0/0",
    "::/0"]
  }

}
