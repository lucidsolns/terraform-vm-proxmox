/*
 * The API requires credentials. Use an API key (c.f. username/password), by going to the
 * web UI 'Datacenter' -> 'Permissions' -> 'API Tokens' and create a new set of credentials.
 *
*/
variable "pm_api_url" {
  description = "The proxmox api endpoint"
  default     = "https://proxmox:8006/api2/json"
}

//
// see
//  - https://thenewstack.io/automate-k3s-cluster-installation-on-flatcar-container-linux/
//
variable "target_node" {
  description = "The name of the proxmox-ve node to provision the VM on"
  type        = string
}

variable "pm_user" {
  description = "A username for password based authentication of the Proxmox API"
  type        = string
  default     = "root@pam"
}

variable "pm_password" {
  description = "A password for password based authentication of the Proxmox API"
  type        = string
  sensitive   = true
  default     = ""
}

variable "bridge" {
  default = "vmbr0"
  type    = string
}

variable "network_tag" {
  default = 0
  type    = number
}
