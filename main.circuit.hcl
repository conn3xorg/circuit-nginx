locals {
  root = "/var/www/html"

  fw_open  = "if firewall-cmd --state >/dev/null 2>&1; then firewall-cmd -q --add-port=${var.port}/tcp && firewall-cmd -q --permanent --add-port=${var.port}/tcp; elif command -v ufw >/dev/null 2>&1; then ufw allow ${var.port}/tcp; fi"
  fw_check = "if firewall-cmd --state >/dev/null 2>&1; then firewall-cmd -q --query-port=${var.port}/tcp && firewall-cmd -q --permanent --query-port=${var.port}/tcp; elif command -v ufw >/dev/null 2>&1; then ufw show added | grep -qx 'ufw allow ${var.port}/tcp'; fi"
}

circuit "nginx" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "package" {
    package {
      name = "nginx"
    }
  }

  # Debian and Ubuntu ship a default site that claims default_server on
  # port 80. The Red Hat family has no such file, so this does nothing there.
  step "debian_default_site" {
    command {
      command = "rm -f /etc/nginx/sites-enabled/default"
      removes = "/etc/nginx/sites-enabled/default"
    }
    notify = [handler.reload]
  }

  step "root" {
    directory {
      path = local.root
    }
  }

  step "index" {
    file {
      path    = "${local.root}/index.html"
      content = var.index_html
    }
  }

  step "site" {
    file {
      path    = "/etc/nginx/conf.d/circuit-nginx.conf"
      content = <<-EOT
        # Managed by circuit-nginx. Changes made here are put back on the next apply.
        server {
            listen ${var.port} default_server;
            listen [::]:${var.port} default_server;
            server_name _;
            root ${local.root};
            index index.html;
        }
      EOT
    }
    notify = [handler.reload]
  }

  step "service" {
    service {
      name    = "nginx"
      state   = "started"
      enabled = true
    }
  }

  # firewall = "auto": firewalld if it's running, otherwise ufw if it's
  # installed. On a host with neither, this does nothing.
  step "firewall_auto" {
    for_each = var.firewall == "auto" ? { port = var.port } : {}
    command {
      command = local.fw_open
      unless  = local.fw_check
    }
  }

  step "firewalld_package" {
    for_each = var.firewall == "firewalld" ? { firewalld = true } : {}
    package {
      name = "firewalld"
    }
  }

  step "firewalld_service" {
    for_each = var.firewall == "firewalld" ? { firewalld = true } : {}
    service {
      name    = "firewalld"
      state   = "started"
      enabled = true
    }
  }

  step "firewalld_port" {
    for_each = var.firewall == "firewalld" ? { port = var.port } : {}
    firewalld {
      port = "${item.value}/tcp"
    }
  }

  step "ufw_package" {
    for_each = var.firewall == "ufw" ? { ufw = true } : {}
    package {
      name = "ufw"
    }
  }

  step "ufw_port" {
    for_each = var.firewall == "ufw" ? { port = var.port } : {}
    ufw {
      action = "allow"
      port   = "${item.value}/tcp"
    }
  }

  handler "reload" {
    service {
      name   = "nginx"
      action = "reload"
    }
  }
}
