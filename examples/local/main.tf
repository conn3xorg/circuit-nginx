variable "port" {
  type    = number
  default = 2222
}

module "web" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"
  index_html           = "<!doctype html>\n<title>circuit-nginx</title>\n<p>Hello from circuit-nginx.</p>\n"
}
