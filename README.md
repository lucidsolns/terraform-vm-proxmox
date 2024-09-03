# terraform-proxmox-vm

A Terraform module to create Proxmox VMs with support for:
   - butane/ignition configurations
   - virtiofs filesystems
   - plan9f filesystems

A [butane](https://coreos.github.io/butane/) configuration provides a human
readable YAML configuration to perform first time boot configuration of 
a VM with a machine readable JSON [ignition](https://coreos.github.io/ignition)
configuration. 

Virtiofs allows directories to be exported from the host into a VM. First
class support for virtiofs is not available in Proxmox VE v8.0, but work
is being done to provide native support for virtiofs.

Proxmox VE v8.0 supports a single hookscript per VM. If extending the
functionality of Proxmox VE via a hookscript then a single monlithic
hookscript doesn't allow modular extension of functionality. This module
provides support for multiple proxmox hookscripts. 

The Proxmox API is highly constrained. The Proxmox provider used is further constrained.
This module is a series of compromises and workaround to allow a VM to be provisioned
within seconds.

This module allows multiple VMs to be provisioned at once. This is useful for 
provisioning small static k8s/k3s clusters.

This module has been developed with Proxmox VE v8.x. The VM being provsioned is
usually Flatcar Linux (to run container workloads). However there is nothing
specific about this script that requires the VM to be running flatcar.

# Prerequisites

To use this Terraform module, the following pre-requisites must be met:
1. Add your root proxmox credentials to a `.tfvars` file
1. Install the hookscript on your Proxmox host, into the `local:snippets` storage
1. Create a VM template (e.g. Flatcar Linux) (see example `makeflatcarproxmoxtemplate`)
    - the template **must** have the hookscript set to `multi-hookscript.pl`
1. Install [terraform-provider-proxmox](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs) v2.9.15 or greater 
1. Install `virtiofsd` (rust) in `/usr/local/bin` 

The example scripts require a `.tfvars` file with your proxmox URL, username,
and password.

Three hookscripts are provided with this module. They must be available in
a snippets directory and must be executable. They have been tested in the 
`local:` storage, which maps to `/var/lib/vz/` directory.

A VM template needs to be created that this module can clone. This can
be any operating system that you choose that has ignition support
and/or virtiofs support as required. The template **must** set the hookscript
to `local:snippets/multi-hookscript.pl` (this is because it is not supported to
set the hookscript via the terraform module)

As of November 2023 the latest version of the Telemate/proxmox provider is v2.9.14
which has a few issues that result in the provider crashing with this script. They have been fixed
in the source code, but not formally released. A Windows build of Telmate/proxmox v2.9.15
has been provided that can be copied to your sample so that `terraform init` is successfully.

Compile or copy the `[virtiofsd](https://share.lucidsolutions.co.nz/pub/debian/bookworm/virtiofsd-1.8.0/)`
to `user/local/bin` so that directories can be shared with virtiofs.

# Multi-hookscript

Support for multiple hookscripts is provided via a hookscript. The multi-hookscript
script reads its configuration from the VM description. It then chains all calls
for each phase to the configured scripts. This allows small functional
hookscripts to be added to the system.

It is hoped that at some stage the proxmox configuration and the API could support
multiple hookscripts natively. This would mean the description field of 
the configuration would not need to be hijacked for this purpose. 

# Butane/Ignition

This support allows 'cattle' (c.f. 'pet) type VM's to be configured via a Terraform
provisioning script. This is not natively supported by Proxmox VE v8.x. Proxmox
VE v.8.x does support cloud-init.

Testing of this feature has been done with Flatcar Linux.

The terraform script transfers the ignition configuration as a resource
to a cloud-init ISO image in Proxmox VE with a name based on the VM id. The hookscript
is then configured to extract the configuration from the cloud-init ISO at
VM pre-start phase and put it in the `/etc/pve/local/ignition/<VM_ID>.ign`
file. The QEMU arguments reference this file as a firmware configuration
via the `fw_cfg` option. The ignition JSON content can be viewed in the
target Linux VM in the file `/sys/firmware/qemu_fw_cfg/by_name/opt/org.flatcar-linux/config/raw`.

This module will create an ignition configuration per VM (when multiple VMs
are provisioned). This means that small tweaks per VM can be specified (however
this moves the VMs further away from being 'cattle'). A minimal set of variables
are passed through to the Butane configuration render function.

# Virt IO Filesystem

This supports exporting directories from the Proxmox host into a VM. Multiple directories
are supported.

The VM operating system must support virtiofs ([`CONFIG_VIRTIO_FS`](https://www.kernelconfig.io/config_virtio_fs))
to allow it to mount the host directory. At the time of writing Flatcar Linux doesn't
support virtiofs, however Alpine Linux does support virtiofs.

The virtiofs support is implemented via QEMU arguments and running an instance of the 
rust based `virtiofsd` daemon per shared directory. A precompiled x86_64 rust binary
is available [here](https://share.lucidsolutions.co.nz/pub/debian/bookworm/virtiofsd-1.8.0/),
or it can be compiled from source.

Although Proxmox VE v8.x doesn't support virtio filesystem, there are patches. Support
for the API is promised. The changes to his script should be minimal when that support
arrives. The names are variables used by this module have been taken from the patch
to ease future transition.

# Plan9 Filesystem

This supports exporting directories from the Proxmox host into a VM. Multiple directories
are supported.

If the VM supports virtiofs then it seems a better option. As of November 2023, Flatcar
Linux doesn't support virtiofs so the plan9fs is used for these VMs.

The terraform for plan9fs support doesn't need a hookscript or a daemon. It simply
sets the QEMU options at VM configuration time.

## Known Limitations

As of November 2023, the following limitations and residuals have been observed:

1. The Proxmox API requires the 'root@pam' user to provision 'args'. Using
   an API key doesn't work, and using an API key for root also doesn't work,
   as the username 'root@pam!terraform' doesn't match the required identity 
   of 'root@pam' which is hardcoded in some places.

2. The Qemu command line parsing requires the Ignition configuration to have all
   comma's escaped with another comma (i.e. a double comma). This means it is far
   easier and more successful to use the 'file=' option (rather than 'string=')
   fw_cfg option.

3. When creating a Proxmox UEFI VM with a pre-made image, the special `file=<storage>:0`
   syntax must be used. e.g. if the node local disk is called 'local' then the syntax would be:
```
   --efidisk0 "file=local:0,import-from=flatcar_production_qemu_image.img,efitype=4m,format=raw,pre-enrolled-keys=1"
```

4. Although the flatcar linux qemu image has a `.img` extension, it is
   a [qcow2](https://en.wikipedia.org/wiki/Qcow) formatted file. The image has multiple partitions.

5. The documentation isn't clear as to the correct way to mount UEFI code partitions as
   a read-only volume. It is unclear how to specify a pflash drive for the UEFI code. To see
   the Qemu configuration run `qm showcmd <vm id> --pretty`, which shows the two EFI
   pflash drives.

6. The Terraform Telmate/Proxmox provider doesn't support setting the hookscript upon create, thus
   the hookscript must be set in the template and inherited to child VM's.

7. The proxmox hook script locks the vm configuration - thus stopping the hook script
   from modifying/mutating the configuration. Even if the configuration is changed the
   Proxmox *start* code will not reload the changes after the hookscript runs.

8. There appears to be limitation on the length of the ignition file to about 8k when
   it is put into the description field.
   It is unclear where this limitation is imposed, as the internal code seems to limit
   the description field to 64kbytes. This renders the strategy of hijacking the description
   field as ineffective for all but trivial VM's. The description field is changeable by a user
   in the 'notes' section of the UI - changing the description may break the hookscript
   configuration. Markdown is used in the description to try and make clear which
   bit is configuration. 

9. The Terraform provider Telmate/Proxmox can generate duplicate MAC addresses when
   provisioning multiple VMs. IPv6 notices the duplicate/collision and doesn't complete
   SLAAC, thus the VM doesn't get IPv6 addresses.

# Links

- https://austinsnerdythings.com/2021/09/01/how-to-deploy-vms-in-proxmox-with-terraform/

### Flatcar

- https://www.flatcar.org/
- Flatcar releases (https://www.flatcar.org/releases)
- https://www.flatcar.org/docs/latest/installing/vms/libvirt/
- https://github.com/flatcar/Flatcar/issues/430
- https://github.com/flatcar/ignition

### Ignition
- https://coreos.github.io/ignition
- https://github.com/flatcar/ignition
- https://www.iana.org/assignments/media-types/application/vnd.coreos.ignition+json

### Terraform

- https://registry.terraform.io/providers/Telmate/proxmox/latest
- https://registry.terraform.io/providers/Telmate/proxmox/latest/docs/resources/vm_qemu
- https://github.com/poseidon/terraform-provider-ct
- https://registry.terraform.io/providers/poseidon/ct/latest/docs
- https://www.flatcar.org/docs/latest/provisioning/config-transpiler/


### Proxmox
- https://pve.proxmox.com/wiki/Manual:_qm.conf

### Qemu
- https://github.com/qemu/qemu/blob/master/docs/specs/fw_cfg.rst
- https://www.qemu.org/docs/master/specs/fw_cfg.html

### UEFI
- https://joonas.fi/2021/02/uefi-pc-boot-process-and-uefi-with-qemu/#uefi-is-not-bios

