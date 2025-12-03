#!/bin/bash

handle_error() {
    echo "Error: $1" >&2
    exit 1
}

is_template_exists() {
    local template_name=$1
    local template_vmid=$(qm list | awk -v name="$template_name" '$2 == name {print $1; exit}')

    echo "${template_vmid}"
}

deploy_vm() {
    local template_name=$1
    local new_vmid=$2
    local new_vm_name=$3
    
    local bridge="vmbr0"
    local disk_size=30

    local template_vmid

    echo "Checking for template '${template_name}'..."
    template_vmid=$(is_template_exists "${template_name}")

    if [[ -z "${template_vmid}" ]]; then
        handle_error "Template named '${template_name}' not found. Create it first using the template creation script."
    fi
    
    echo "Cloning template ${template_vmid} to VM ${new_vmid} (${new_vm_name})..."
    qm clone "${template_vmid}" "${new_vmid}" --full true --name "${new_vm_name}"

    qm set ${new_vmid} --delete net0
    qm set "${new_vmid}" --net0 virtio,bridge="${bridge}" 
    qm disk resize "${new_vmid}" scsi0 "+${disk_size}G"

    echo "Starting VM ${new_vmid}..."
    qm start "${new_vmid}"
}

main() {
    if [ "$EUID" -ne 0 ]; then
        echo "Run as root or with sudo." >&2
        exit 1
    fi
    
    local new_vmid="$(pvesh get /cluster/nextid)"
    local os_choice
    local template_name
    local new_vm_name
    local os_short_name
    local response
        
    echo "Select the operating system template for deployment:"
    echo "1) Debian 12"
    echo "2) Ubuntu 22.04"
    echo "3) AlmaLinux 8"
    echo "---"
    read -p "Enter the number (1-3): " os_choice
    
    case "$os_choice" in
        1)
            template_name="debian-12-tmp"
            os_short_name="debian12"
            ;;
        2)
            template_name="ubuntu-22.04-tmp"
            os_short_name="ubuntu22"
            ;;
        3)
            template_name="almalinux-8-tmp"
            os_short_name="alma8"
            ;;
        *)
            echo "Invalid choice. Enter a number from 1 or 3"
            exit 1
            ;;
    esac
    
    new_vm_name="${os_short_name}-vm-${new_vmid}"
    deploy_vm "${template_name}" "${new_vmid}" "${new_vm_name}"
}

main