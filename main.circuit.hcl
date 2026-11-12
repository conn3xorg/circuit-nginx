locals {
  root = "/var/www/html"

  # Another circuit may be installing ufw right now. Mid-install the binary
  # is already there but ufw.conf, a conffile, isn't, and ufw fails without
  # it, so wait up to five minutes for the install to finish.
  ufw_wait = "i=0; while [ ! -e /etc/ufw/ufw.conf ] || dpkg-query -W -f='$${db:Status-Status}' ufw 2>/dev/null | grep -qE '^(unpacked|half-installed|half-configured|triggers-awaited|triggers-pending)$'; do [ $i -ge 300 ] && break; i=$((i + 1)); sleep 1; done"
  # The same for firewalld, which only counts once it's running: wait, up
  # to five minutes, while firewalld is being installed, or is enabled but
  # hasn't started since boot, as just after another circuit installs it.
  # One stopped on purpose has started before, and one that failed at boot
  # won't start by waiting, so a plan doesn't wait for either.
  # dn[f] keeps pgrep -f from matching this script's own command line.
  fwd_wait = "i=0; while pgrep -f 'dn[f].* install .*firewalld' >/dev/null || { systemctl -q is-enabled firewalld 2>/dev/null && ! systemctl -q is-active firewalld && [ \"$(systemctl show -P ActiveEnterTimestampMonotonic firewalld)\" = 0 ] && [ \"$(systemctl show -P ActiveState firewalld)\" != failed ]; }; do [ $i -ge 300 ] && break; i=$((i + 1)); sleep 1; done"
  # systemctl answers straight away. firewall-cmd --state on a stopped
  # firewalld waits about ten seconds for D-Bus first, on every plan.
  site_test = join("; ", [
    "m=$(mktemp /etc/nginx/.conn3x-test.XXXXXX)",
    "inc=$(mktemp)",
    "trap 'rm -f \"$m\" \"$inc\"' EXIT",
    "for f in /etc/nginx/conf.d/*.conf; do if [ -e \"$f\" ] && [ \"$f\" != /etc/nginx/conf.d/circuit-nginx.conf ]; then echo \"include $f;\"; fi; done > \"$inc\"",
    "echo \"include %s;\" >> \"$inc\"",
    "sed -e '\\#^[[:space:]]*include /etc/nginx/conf.d/\\*\\.conf;#{' -e \"r $inc\" -e 'd' -e '}' /etc/nginx/nginx.conf > \"$m\"",
    "grep -qF \"include %s;\" \"$m\" || { echo 'nginx.conf has no include /etc/nginx/conf.d/*.conf; line to test the site in.' >&2; exit 1; }",
    "nginx -t -q -c \"$m\"",
  ])
  # @PORT@ is the port each firewall_auto item opens.
  fw_open  = "${local.fwd_wait}; if systemctl -q is-active firewalld && firewall-cmd --state >/dev/null 2>&1; then firewall-cmd -q --add-port=@PORT@/tcp && firewall-cmd -q --permanent --add-port=@PORT@/tcp; elif command -v ufw >/dev/null 2>&1; then ${local.ufw_wait}; ufw allow @PORT@/tcp; fi"
  fw_check = "${local.fwd_wait}; if systemctl -q is-active firewalld && firewall-cmd --state >/dev/null 2>&1; then firewall-cmd -q --query-port=@PORT@/tcp && firewall-cmd -q --permanent --query-port=@PORT@/tcp; elif command -v ufw >/dev/null 2>&1; then ufw show added | grep -qx 'ufw allow @PORT@/tcp'; fi"

  # The ports to open. The keys stay "port" and "tls_port", so turning TLS
  # on or off doesn't touch the plain port's firewall steps.
  ports = merge({ port = var.port }, var.tls_self_signed ? { tls_port = var.tls_port } : {})

  tls_key  = "/etc/nginx/circuit-nginx.key"
  tls_cert = "/etc/nginx/circuit-nginx.crt"
  # Addresses go in the certificate's ip_addresses, everything else in its
  # dns_names.
  tls_ips = [for n in var.tls_names : n if can(cidrhost("${n}/32", 0)) || can(cidrhost("${n}/128", 0))]
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

  # A key and a self-signed certificate, made on the host, so the key never
  # leaves it. The certificate is renewed 30 days before it expires, and
  # nginx reloads to pick it up.
  step "tls_openssl" {
    when = var.tls_self_signed
    package {
      name = "openssl"
    }
  }

  step "tls_key" {
    when = var.tls_self_signed
    tls_private_key {
      path = local.tls_key
    }
  }

  step "tls_cert" {
    when = var.tls_self_signed
    tls_self_signed_cert {
      path         = local.tls_cert
      key_path     = local.tls_key
      common_name  = length(var.tls_names) > 0 ? var.tls_names[0] : each.key
      dns_names    = length(var.tls_names) > 0 ? [for n in var.tls_names : n if !contains(local.tls_ips, n)] : [each.key]
      ip_addresses = local.tls_ips
      days         = var.tls_days
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

  # nginx -t on the candidate before it replaces the site file. nginx.conf
  # includes conf.d/*.conf, which would pull in the old site file next to the
  # candidate, so the test reads a throwaway copy of nginx.conf with that line
  # swapped for every other file in conf.d plus the candidate, %s. It sits
  # next to nginx.conf so any relative include resolves the same way.
  step "site" {
    file {
      path     = "/etc/nginx/conf.d/circuit-nginx.conf"
      validate = local.site_test
      content  = <<-EOT
        # Managed by circuit-nginx. Changes made here are put back on the next apply.
        server {
            listen ${var.port} default_server;
            listen [::]:${var.port} default_server;
            server_name _;
            root ${local.root};
            index index.html;
        }
        %{if var.tls_self_signed~}
        server {
            listen ${var.tls_port} ssl default_server;
            listen [::]:${var.tls_port} ssl default_server;
            server_name _;
            ssl_certificate ${local.tls_cert};
            ssl_certificate_key ${local.tls_key};
            root ${local.root};
            index index.html;
        }
        %{endif~}
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
    for_each = var.firewall == "auto" ? local.ports : {}
    command {
      command = replace(local.fw_open, "@PORT@", tostring(item.value))
      unless  = replace(local.fw_check, "@PORT@", tostring(item.value))
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
    for_each = var.firewall == "firewalld" ? local.ports : {}
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
    for_each = var.firewall == "ufw" ? local.ports : {}
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
