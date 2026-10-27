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
