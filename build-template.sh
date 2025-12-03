#!/bin/bash

handle_error() {
    echo "Error: $1" >&2
    exit 1
}

check_existing_template_by_name() {
    local vm_name=$1
    local existing_vmid=$(qm list | awk -v name="$vm_name" '$2 == name {print $1; exit}')

    if [ ! -z "$existing_vmid" ]; then
        echo "Template or VM with name '${vm_name}' already exists with ID ${existing_vmid}. Skipping creation." >&2
        return 0
    else
        return 1
    fi
}

download_image() {
    local image_name=$1
    local image_url=$2
    local download_dir=$3
    local full_image_path="${download_dir}/${image_name}"

    echo "Downloading image ${image_name}..."
    wget -O "${full_image_path}" --continue "${image_url}/${image_name}"
    
    if [ ! -f "${full_image_path}" ]; then
        handle_error "Failed to download image."
    fi
}

create_vm() {
    local vmid=$1
    local vm_name=$2
    local cpu_type=$3
    local static_ip_cidr=$4

    local memory=2048
    local cores=2
    local bridge="vmbr0"
    local gateway="192.168.0.1"

    local ipconfig_setting="ip=${static_ip_cidr},gw=${gateway}"

    echo "Creating VM ${vm_name} with ID ${vmid}..."
    qm create "${vmid}" --name "${vm_name}" --memory "${memory}" --cpu "${cpu_type}" --cores "${cores}" --ostype l26 --agent 1
    qm set "${vmid}" --net0 virtio,bridge="${bridge}" --ipconfig0 ip="${static_ip_cidr}",gw="${gateway}"
}

configure_disks() {
    local vmid=$1
    local image_name=$2
    local storage=$3
    local download_dir=$4
    local image_format=$5

    local full_image_path="${download_dir}/${image_name}"
    local disk_path

    qm importdisk "${vmid}" "${full_image_path}" "${storage}" --format "${image_format}"

    disk_path=$(qm config "${vmid}" | grep "unused0" | awk '{print $2}' | sed 's/,.*//')
    if [ -z "$disk_path" ]; then
        handle_error "Could not find path to imported disk."
    fi

    echo "Configuring disks for VM ${vmid}..."
    qm set "${vmid}" --scsihw virtio-scsi-pci --scsi0 "${disk_path}"
    qm set "${vmid}" --boot c --bootdisk scsi0
    qm set "${vmid}" --serial0 socket
}

configure_cloudinit() {
    local vmid=$1
    local os_name=$2
    local storage=$3
    local root_pass
    local ssh_pub_key 
    
    if [ -f .env ]; then 
        source .env
        root_pass="${ROOT_PASS}"
        ssh_pub_key="${SSH_PUB_KEY}"
    else
        handle_error ".env file not found. ROOT_PASS and SSH_PUB_KEY are required."
    fi

    if [ -z "$root_pass" ] && [ -z "$ssh_pub_key" ]; then
        handle_error "ROOT_PASS and SSH_PUB_KEY are not set in the .env file."
    fi
    
    local cloudinit_template_dir="./cicustom"
    local template_file="${cloudinit_template_dir}/${os_name}.yaml"
    local path_to_snippet="/var/lib/vz/snippets"
    local snippet_filename="user-data-${os_name}.yaml"
    local full_snippet_path="${path_to_snippet}/${snippet_filename}"
    local template_content
    local final_content

    if [ ! -f "${template_file}" ]; then
        handle_error "Cloud-Init template file not found: ${template_file}. Please create it."
    fi

    echo "Configuring Cloud-Init for VM ${vmid} using template ${template_file}..."
    mkdir -p "${path_to_snippet}"

    template_content="$(< ${template_file})" 

    final_content=$(echo "${template_content}" | \
        sed "s|{{ ROOT_PASS }}|${root_pass}|" | \
        sed "s|{{ SSH_PUB_KEY }}|${ssh_pub_key}|")

    echo "${final_content}" > "${full_snippet_path}"
    qm set "${vmid}" --ide2 "${storage}:cloudinit"
    qm set "${vmid}" --cicustom "user=${storage}:snippets/${snippet_filename}"
}

create_template() {
    local vmid=$1
    echo "Creating template from VM ${vmid}..."
    qm template "${vmid}"
}

cleanup() {
    local download_dir=$1
    local image_name=$2
    
    echo "Removing temporary image ${download_dir}/${image_name}..."
    rm -f "${download_dir}/${image_name}"
}

main() {
    if [ "$EUID" -ne 0 ]; then
        echo "Run as root or with sudo." >&2
        exit 1
    fi

    local download_dir="/tmp"
    local storage="local"
    local image_format="qcow2"
    local cpu_type="host"
    local vmid="$(pvesh get /cluster/nextid)"

    local os_choice
    local os_name
    local vm_name
    local image_name
    local image_url
    local static_ip_cidr

    echo "Select the operating system for the VM template creation:"
    echo "1) Debian 12"
    echo "2) Ubuntu 22.04"
    echo "3) AlmaLinux 8"
    echo "---"
    read -p "Enter the number (1-3): " os_choice

    case "$os_choice" in
        1)
            os_name="debian"
            image_name="debian-12-generic-amd64.qcow2"
            image_url="https://cdimage.debian.org/images/cloud/bookworm/latest/"
            vm_name="debian-12-tmp"
            static_ip_cidr="192.168.0.20/24"
            ;;
        2)
            os_name="ubuntu"
            image_name="jammy-server-cloudimg-amd64.img"
            image_url="https://cloud-images.ubuntu.com/jammy/current/"
            vm_name="ubuntu-22.04-tmp"
            static_ip_cidr="192.168.0.21/24"
            ;;
        3)
            os_name="almalinux-8"
            image_name="AlmaLinux-8-GenericCloud-latest.x86_64.qcow2"
            image_url="https://repo.almalinux.org/almalinux/8/cloud/x86_64/images/"
            vm_name="almalinux-8-tmp"
            static_ip_cidr="192.168.0.22/24"
            ;;
        *)
            echo "Invalid choice. Enter a number from 1 to 3"
            exit 1
    esac

    if check_existing_template_by_name "${vm_name}"; then
        exit 0
    fi
    
    download_image "${image_name}" "${image_url}" "${download_dir}"
    create_vm "${vmid}" "${vm_name}" "${cpu_type}" "${static_ip_cidr}"
    configure_disks "${vmid}" "${image_name}" "${storage}" "${download_dir}" "${image_format}"
    configure_cloudinit "${vmid}" "${os_name}" "${storage}" 
    create_template "${vmid}"
    cleanup "${download_dir}" "${image_name}"

    echo "---"
    echo "SUCCESS: Template created for ${vm_name}."
    echo "New Template ID: ${vmid}"
    echo "---"
}

main "$1"