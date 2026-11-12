variable "hosts" {
  type        = any
  description = "The hosts to configure: a map of names to addresses, or to host objects with an address and settings such as host_key."

  validation {
    condition     = can(keys(var.hosts)) && alltrue([for v in values(var.hosts) : can(tostring(v)) || can(tostring(v.address))])
    error_message = "hosts must be a map whose values are addresses, or objects with an address."
  }
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "The user to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "The SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key file. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "The known_hosts file to check host keys against. When null, Conn3x uses ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run every command as root through sudo. Set this when ssh_user isn't root."
}

variable "index_html" {
  type        = string
  default     = "<!doctype html>\n<title>It works</title>\n<p>nginx is running. Set index_html to serve your own page.</p>\n"
  description = "Content of the site's index.html."
}

variable "port" {
  type        = number
  default     = 80
  description = "The port nginx listens on and the firewall opens."

  validation {
    condition     = var.port >= 1 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port must be a whole number from 1 to 65535."
  }
}

variable "firewall" {
  type        = string
  default     = "auto"
  description = "How to open the port: \"auto\" uses firewalld or ufw if the host has one, \"firewalld\" or \"ufw\" installs and uses that one, \"none\" leaves the firewall alone."

  validation {
    condition     = contains(["auto", "firewalld", "ufw", "none"], var.firewall)
    error_message = "firewall must be \"auto\", \"firewalld\", \"ufw\" or \"none\"."
  }
}

variable "tls_self_signed" {
  type        = bool
  default     = false
  description = "Make a key and a self-signed certificate on each host, and serve the site over HTTPS on tls_port too. For labs and internal services without a CA."
}

variable "tls_port" {
  type        = number
  default     = 443
  description = "The port nginx serves HTTPS on, with tls_self_signed, and the port the firewall opens for it."

  validation {
    condition     = var.tls_port >= 1 && var.tls_port <= 65535 && floor(var.tls_port) == var.tls_port
    error_message = "tls_port must be a whole number from 1 to 65535."
  }

  validation {
    condition     = !var.tls_self_signed || var.tls_port != var.port
    error_message = "tls_port must differ from port."
  }
}

variable "tls_names" {
  type        = list(string)
  default     = []
  description = "Names and addresses the certificate is for. The first is its common name. When empty, it's for the host's name in hosts."
}

variable "tls_days" {
  type        = number
  default     = 365
  description = "How long each certificate is valid, from 31 to 3650 days. It's renewed when 30 days are left."

  validation {
    condition     = var.tls_days >= 31 && var.tls_days <= 3650 && floor(var.tls_days) == var.tls_days
    error_message = "tls_days must be a whole number from 31 to 3650."
  }
}
