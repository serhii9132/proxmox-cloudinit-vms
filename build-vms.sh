#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

is_template_exists() {
    local template_name=$1
    local template_vmid=$(qm list | awk -v name="$template_name" '$2 == name {print $1; exit}')

    echo "${template_vmid}"
}

deploy_vm() {
    local template_name=$1
    local new_vmid=$2
    local new_vm_name=$3
    local new_vm_ip=$4
    
    local bridge="vmbr0"
    local disk_size=30

    local template_vmid

    echo "Checking for template '${template_name}'..."
    template_vmid=$(is_template_exists "${template_name}")

    if [[ -z "${template_vmid}" ]]; then
        echo "Template named '${template_name}' not found. Create it first using the template creation script."
        exit 1
    fi
    
    echo "Cloning template ${template_vmid} to VM ${new_vmid} (${new_vm_name})..."
    qm clone "${template_vmid}" "${new_vmid}" --full true --name "${new_vm_name}"

    qm set "${new_vmid}" --net0 virtio,bridge="${bridge}" --ipconfig0 ip="${new_vm_ip}/${MASK},gw=${GATEWAY}"
    
    qm disk resize "${new_vmid}" scsi0 "+${disk_size}G"

    echo "Configuration complete:"
    echo "  - VMID: ${new_vmid}"
    echo "  - Name: ${new_vm_name}"
    echo "  - IP:   ${new_vm_ip}/${MASK}"
    echo "  - GW:   ${GATEWAY}"
    
    echo "Starting VM ${new_vmid}..."
    qm start "${new_vmid}"
}

main() {
    if [ "$EUID" -ne 0 ]; then
        echo "Run as root or with sudo." >&2
        exit 1
    fi
    
    if [ ! -f .env ]; then
        echo ".env doesn't exist... Exit"
        exit 1
    fi

    source .env

    local num_vms_to_deploy
    local os_choice
    local template_name
    local os_short_name
    
    echo "Select the operating system template for deployment:"
    echo "1) Debian 12"
    echo "2) Debian 13"
    echo "3) Ubuntu 22.04"
    echo "4) AlmaLinux 8"
    echo "---"
    read -p "Enter the number (1-4): " os_choice
    
    case "$os_choice" in
        1)
            template_name="debian-12-tmp"
            os_short_name="debian12"
            ;;
        2)
            template_name="debian-13-tmp"
            os_short_name="debian13"
            ;;
        3)
            template_name="ubuntu-22.04-tmp"
            os_short_name="ubuntu22"
            ;;
        4)
            template_name="almalinux-8-tmp"
            os_short_name="alma8"
            ;;
        *)
            echo "Invalid choice. Enter a number from 1 to 4."
            exit 1
            ;;
    esac
    
    echo "---"
    read -p "Enter the number of VMs to deploy (1-3): " num_vms_to_deploy
    if ! [[ "$num_vms_to_deploy" =~ ^[1-3]$ ]]; then
        echo "Invalid number of VMs. Must be between 1 and 3."
        exit 1
    fi
    
    echo -e "\nStarting deployment of ${num_vms_to_deploy} VMs from template '${template_name}'..."

    for i in $(seq 1 ${num_vms_to_deploy}); do
        local new_vmid="$(pvesh get /cluster/nextid)"
        local new_vm_name="${os_short_name}-vm-${new_vmid}"
        local new_vm_ip="${SUBNET_BASE}${new_vmid}" 
        
        deploy_vm "${template_name}" "${new_vmid}" "${new_vm_name}" "${new_vm_ip}" "${GATEWAY}"
    done
}

main