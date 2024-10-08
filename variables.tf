variable "vmid" {
  description = "The unique Proxmox id for the VM."
  type        = number
}

variable "name" {
  type        = string
  default     = "Flatcar-Linux"
  description = "The name of the VM. This is used by Proxmox for display purposes."
}

variable "description" {
  type        = string
  description = <<-EOF
    A markdown description that is put into the VM notes fields.

    This module hijacks and abuses the description/notes field of the Proxmox
    VM configuration. This is because it is one of the few text fields where
    data can be encoded. The data in description **must** not be changed.

    The description is URL encoded into a comment at the top of the PVE
    configuration file for the VM.
  EOF
  default     = null
  nullable    = true
}

variable "vm_count" {
  description = <<-EOF
    The number of VMs to provision.

    This allows cattle (c.f. pets) to be provisioned. Subsequent VM will
    be provisioned with an incrementing ID. The name will be suffixed with
    the index and count of VM's.

    Variables are passed to the ignition renderer so that the configuration
    can be tweaked for each instance.
  EOF
  type        = number
  default     = 1
}


variable "tags" {
  description = "Tags to apply to the VM"
  type        = list(string)
  default     = ["terraform"]
}

variable "butane_conf" {
  type        = string
  description = <<-EOF
     The optional name of a Butane configuration file for the VM.

     When butane configuration is provided then the VM will be configured:
       - the butane will be compiled for each VM instance to ignition
       - the ignition will be uploaded as a cloud-init ISO image
       - the VM will get a hookscript to copy the ISO 'meta' file to a PVE file
       - the VM will be configured with a fw_cfg to load the ignition file

     The following terraform template parameters are available:
         vm_id    - the numeric unique identifier for the virtual machine being provisioned
         vm_name  - the name for the VM (this will be mutated based on the provided name)
         vm_count - the number of VMs being provisioned by the template (normally 1)
         vm_index - the zero based index of the VM being provisioned
  EOF
  default     = null
}

variable butane_path {
  description = <<-EOF
     The path used to allow embedding local files.

     If not set, the directory of the `butane_conf` file will be used.

     If this is set then the use of local files is enabled: e.g. in the butane files section:

         - path: /etc/docker-compose.yaml
           contents:
             local: docker-compose.yaml

  EOF
  type        = string
  default     = null
}

variable "butane_conf_snippets" {
  type        = list(string)
  default     = []
  description = "Additional YAML Butane configuration(s) for the VM (experimental)"
}

variable "target_node" {
  description = "The name of the target proxmox node where the VM should be provisioned"
  type        = string
}

variable "storage" {
  description = "The name of the storage used for storing VM images"
  type        = string
  default     = "local"
}

variable "template_name" {
  description = <<-EOF
      The name of a VM that has been converted to a template. The creation of this
      process is manual, and has not been automated.

      The template VM **must** have the hookscript set to be the `multi-hookscript.pl`.

      Note: The flatcar qemu image is a qcow2 image, and not a raw disk image as the name implies.

      Steps:
        1. Download the latest flatcar qemu image (noting the version number)
               > wget https://stable.release.flatcar-linux.net/amd64-usr/3510.2.6/flatcar_production_qemu_image.img.bz2
        2. Create a new VM with the name 'flatcar-production-qemu-<version>' (e.g. flatcar-production-qemu-3510.2.6)
               - UEFI boot
               - with no network
               - with no disks
               - delete the CDROM
        3. Decompress the flatcar qcow2 image
               > bunzip2 flatcar_production_qemu_image.img.bz2
        4. Add the qcow2 image to the VM
               > qm importdisk 900 flatcar_production_qemu_image.img vmroot --format qcow2
        5. Adopt the new disk into the VM
               > qm set 900 -efidisk0 vm-900-disk-0.qcow2:0,format=qcow2,efitype=4m,pre-enrolled-keys=1
        6. Convert the VM to a Template

      see
        - https://www.flatcar.org/releases
  EOF
  type        = string
  default     = "flatcar_qemu"
}

variable "full_clone" {
  description = <<-EOF
     Set to `true` to create a full clone, or `false` to create a linked clone.
     See the [docs about cloning](https://pve.proxmox.com/pve-docs/chapter-qm.html#qm_copy_and_clone) for more info.
     Only applies when `clone` is set."
  EOF
  type        = bool
  default     = true
}


variable "cores" {
  description = "The number of CPU cores to allocate to the VM"
  type        = number
  default     = 2
}

variable "cpu" {
  type        = string
  default     = "host"
  description = "The features that are declared for the CPU e.g. x86-64-v2-AES"
}

variable "memory" {
  description = "The memory size of the VM in megabytes"
  type        = number
  default     = 2048
}

variable "networks" {
  description = "An ordered list of network interfaces"
  type        = list(object({
    bridge  = optional(string, "vmbr0")
    tag     = optional(number)
    mtu     = optional(number)
    macaddr = optional(string, null)
  }))
  default = [
    {
      bridge = "vmbr0",
    }
  ]
}

/*
 */
variable "virtiofs" {
  description = <<-EOF
    An ordered list of filesystems paths for the host

    This data structure is used to configure a directory to be exported from
    the host Proxmox into the VM using virtiofs.

    The parameters are modeled on the June 2023 patch by Markus Frank, which
    defines the parameters for each share as 'dirid', 'tag', 'cache' and 'direct-io'.
    Taking this approach should allow for an easy migration to the official support
    once it is fully integrated into proxmox.

    The default setting provisions no virtio filesystems and doesn't provision
    the VM with the required devices and doesn't provision hookscripts.

    see:
      - https://lists.proxmox.com/pipermail/pve-devel/2023-June/057270.html

  EOF
  type        = list(object({
    dirid     = string
    tag       = string
    cache     = optional(string) # auto, always, never
    direct-io = optional(string) # "auto", always", "never"
  }))
  default = [] // no virtiofs shares are performed by default
}

/*
 */
variable "plan9fs" {
  description = <<-EOF
    An ordered list of filesystems paths for the host.

    This data structure is used to configure a directory to be exported from
    the host Proxmox into the VM using plan9fs.

    see:
      - https://wiki.qemu.org/Documentation/9psetup
      - http://www.linux-kvm.org/page/9p_virtio
      - https://pve.proxmox.com/wiki/Manual:_qm.conf
  EOF
  type        = list(object({
    dirid          = string
    tag            = string
    security_model = optional(string, "mapped-xattr") # mapped|mapped-xattr|mapped-file|passthrough|none
    readonly       = optional(bool, false) #
    multidevs      = optional(string, "warn") # remap|forbid|warn
  }))
  default = [] // no plan9 filesystems shares are performed by default
}

variable "os_type" {
  type        = string
  default     = "l26"
  description = "The short OS name identifier"
}

variable "os_type_name" {
  type        = string
  default     = "Linux 2.6 - 6.X Kernel"
  description = "os_type_name='Linux 2.6 - 6.X Kernel'"
}

variable "pm_api_url" {
  description = "The FQDN and path to the API of the proxmox server e.g. https://example.com:8006/api2/json"
  type        = string
}

variable "pm_user" {
  description = <<-EOF
    The username for password based authentication of the Proxmox API

    Due to authorisation checks on the literal 'root', only username/password
    authentication of the root user (`root@pam`) is supported.
  EOF
  type        = string
  default     = "root@pam"
}

variable "pm_password" {
  description = "A password for password based authentication of the Proxmox API"
  type        = string
  sensitive   = true
  default     = ""
}

variable "pm_tls_insecure" {
  description = "leave tls_insecure set to true unless you have trusted proxmox SSL certificate (i.e. not self signed)"
  default     = true
  type        = bool
}
variable "bios" {
  description = "Whether to use UEFI (ovmf) or SeaBIOS"
  default     = "ovmf"
  type        = string
}

variable "agent" {
  description = "Whether the guest will have QEMU agent software running"
  default     = true
  type        = bool
}

variable "onboot" {
  description = "Specifies whether a VM will be started during system bootup"
  type        = bool
  default     = true
}

variable "startup" {
  description = <<-EOF
    Startup and shutdown behavior. Order is a non-negative number defining the general
    startup order. Shutdown in done with reverse ordering. Additionally you can set
    the up or down delay in seconds, which specifies a delay to wait before the next
    VM is started or stopped.

    startup = `[[order=]\d+] [,up=\d+] [,down=\d+]`
  EOF
  type        = string
  default     = "order=999"
}

variable "boot" {
  description = <<-EOF
    The order of boot devices for the VM.

    In general it is expected that VMs will be created with a clone image, thus
    booting off installation media should not be required.

      see:
       - https://pve.proxmox.com/wiki/Manual:_qm.conf#_options
  EOF
  type        = string
  default     = null
}

variable "pool" {
  description = <<-EOF
    The name of a pool resource
  EOF
  type        = string
  default     = null
}

variable "cloud_init_storage" {
  description = <<-EOF
    The storage name to use for storing cloud-init images which are used
    as a container for the butane/ignition files
  EOF
  type        = string
  default     = "local"
}


# An optional list of disks (in module flat list format, rather than hierarchical format).
#
#  see:
#  - https://github.com/Telmate/terraform-provider-proxmox/issues/986
variable "disks" {
  description = "A optional list of disks in a flat format"
  default     = []
  type        = list(object({
    slot    = string # {ide,sata,scsi,virtio}{0,1,2,...}
    storage = optional(string) # e.g. "local"
    type    = optional(string) # disk, cdrom, cloudinit

    id             = optional(number), # computed
    asyncio        = optional(string),
    backup         = optional(bool),
    cache          = optional(string),
    discard        = optional(bool),
    disk_file      = optional(string),
    emulatessd     = optional(bool),
    format         = optional(string),
    iothread       = optional(bool),
    iso            = optional(string),
    linked_disk_id = optional(number),
    passthrough    = optional(bool),
    readonly       = optional(bool),
    replicate      = optional(bool),
    serial         = optional(string),
    size           = optional(string), # computed
    wwn            = optional(string),
  }))
  validation {
    condition = alltrue([
      for item in var.disks : (
      can(regex("[a-zA-Z]{3,6}[0-9]{1,2}", item.slot))
      )
    ])
    error_message = "The slot must be of the form scsi0..scsi31, virtio0..virtio31, sata0..sata31, ide0..ide7"
  }
}
