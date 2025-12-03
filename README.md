Scripts for deployment of virtual machines in the Proxmox VE environment.
Supported images:
- Debian 12
- Ubuntu 22.04
- AlmaLinux 8.10

## Attention
These scripts are used for testing and are not intended for production use. For additional protection, use a user with sudo privileges, SSH authentication, and a combination of IPtables and Fail2ban.

### Notes
- Allowed root login via SSH keys
- Package qemu-guest-agent has been pre-installed
- VM parameters: 
    - CPU: 2 cores
    - RAM: 2 GB
    - Disk: ${base_size_of_cloudinit_image} + 30 Gb 

### Usage
1. Create a .env file in the root of the project with the following content:
```sh
ROOT_PASS='$passwordhash12345'                  # Use: mkpasswd -m sha-512
SSH_PUB_KEY='ssh-ed25519 AAAAC3NzaCAAAAABBBBBCCCCC11... user@hostname'
```
2. Run **bash build-template.sh** to create the template
3. Run **bash build-vms.sh**