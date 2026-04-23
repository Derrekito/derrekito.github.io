---
title: "Building a Private Cloud with OpenStack: Architecture and Planning"
date: 2026-10-12
categories: [Cloud Computing, Infrastructure]
tags: [openstack, private-cloud, virtualization, virtualbox, ubuntu, devops]
---

OpenStack provides an open-source platform for building private cloud infrastructure. Instead of relying entirely on public cloud providers, organizations can deploy compute, storage, and networking services on their own hardware. This series documents a hands-on OpenStack deployment, covering installation, configuration, and operation of each core service.

## What is OpenStack?

OpenStack is a collection of open-source software projects that together create a complete cloud infrastructure platform. Each project handles a specific infrastructure concern:

- **Keystone**: Identity service (authentication and authorization)
- **Nova**: Compute service (virtual machine management)
- **Glance**: Image service (VM templates and snapshots)
- **Neutron**: Networking service (virtual networks, routers, and floating IPs)
- **Horizon**: Dashboard (web-based management interface)
- **Cinder**: Block storage service (persistent volumes)
- **Swift**: Object storage service (distributed file storage)
- **Placement**: Resource tracking (inventory and allocation)
- **RabbitMQ**: Message queue (inter-service communication)

These services interact through REST APIs and message queues to provide a cohesive cloud platform. Keystone handles authentication for all services, Nova launches instances using images from Glance, Neutron provides networking, and so on.

## Why Build Private Cloud?

Public cloud providers offer convenience, but private cloud provides:

- **Control**: Full access to underlying infrastructure and configuration
- **Privacy**: Data never leaves your network
- **Compliance**: Meet regulatory requirements for data residency
- **Cost predictability**: No variable cloud bills for steady workloads
- **Learning platform**: Understand how cloud services actually work

This deployment uses VirtualBox VMs to simulate a multi-node OpenStack environment. While not production-grade, this approach demonstrates the architecture and configuration steps without requiring dedicated hardware.

## Architecture Overview

OpenStack follows a distributed architecture where services run on separate nodes and communicate over the network. This deployment uses one VM per major service:

| Service | Hostname | IP Address | Role |
|---------|----------|------------|------|
| Base Template | basevm | 192.168.56.102 | Template for cloning |
| Keystone | keystone | 192.168.56.103 | Identity, also hosts RabbitMQ and Placement |
| Glance | glance | 192.168.56.104 | Image storage |
| Nova | nova | 192.168.56.105 | Compute controller and hypervisor |
| Neutron | neutron | 192.168.56.106 | Network controller |
| Horizon | horizon | 192.168.56.107 | Web dashboard |
| Cinder | cinder | 192.168.56.108 | Block storage |
| Swift | swift | 192.168.56.109 | Object storage |

Each service follows a standard installation pattern:

1. Clone a VM from the base template
2. Configure networking and hostname
3. Create a database for the service in MariaDB
4. Create a Keystone user for service-to-service authentication
5. Install service packages
6. Configure service files to communicate with other services
7. Initialize the database and start the service

## Configuration Conventions

To simplify the deployment, services follow naming patterns:

- **Database passwords**: `SERVICENAME_DBPASS` (e.g., `GLANCE_DBPASS`)
- **Service passwords**: `SERVICENAME_PASS` (e.g., `GLANCE_PASS`)
- **Hostnames**: Lowercase service name (e.g., `keystone`, `nova`)

These passwords are intentionally simple for a learning environment. Production deployments require strong, randomly-generated passwords and secrets management.

## Prerequisites

This OpenStack deployment requires:

**Hardware**:
- 6+ GB RAM (more is better; 16 GB recommended)
- 6+ CPU cores
- 200+ GB disk space
- VT-x/AMD-V virtualization support enabled in BIOS

**Software**:
- Ubuntu Desktop (host machine)
- VirtualBox 6.1 or later
- Ubuntu Server 24.04.1 LTS (for VMs)

**Knowledge**:
- Linux command-line operations
- Basic networking concepts (IP addressing, routing)
- Text editing (vim, nano, or similar)
- SSH and remote access

## Setting Up VirtualBox

Install VirtualBox on the host Ubuntu system:

```bash
sudo apt install virtualbox
```

After installation, configure a host-only network adapter for VM communication. Open VirtualBox, navigate to **File → Tools → Network Manager**, and create a host-only adapter. This adapter allows the host machine to communicate with VMs while keeping them isolated from the external network.

The host-only adapter typically gets an IP in the `192.168.56.0/24` range. VMs will use static IPs starting from `192.168.56.102`.

## Creating the Base VM Template

All OpenStack service VMs clone from a single base template. This ensures consistency and simplifies setup.

### Install Ubuntu Server

Download Ubuntu Server 24.04.1 LTS and create a new VirtualBox VM:

- **Name**: BaseVM
- **Type**: Linux
- **Version**: Ubuntu (64-bit)
- **Memory**: 2048 MB (adjust based on available RAM)
- **Disk**: 20 GB (dynamically allocated)
- **Network Adapter 1**: NAT (for internet access)
- **Network Adapter 2**: Host-only Adapter (for VM communication)

Boot the VM and complete the Ubuntu Server installation. During installation:

- Create a user account (this series uses `openstack` as the username)
- Enable OpenSSH server
- Accept default partition layout

After installation, verify the Ubuntu version:

```bash
lsb_release -a
```

Expected output:

```
Distributor ID: Ubuntu
Description:    Ubuntu 24.04.1 LTS
Release:        24.04
Codename:       noble
```

### Install Essential Tools

Install basic utilities for system management:

```bash
sudo apt install neovim net-tools ssh
```

Enable and start the SSH daemon:

```bash
sudo systemctl enable ssh
sudo systemctl start ssh
```

### Configure Network Adapters

The base VM needs two network adapters:

- **Adapter 1 (NAT)**: Provides internet access via VirtualBox NAT
- **Adapter 2 (Host-only)**: Enables communication with host and other VMs

Disable cloud-init's network management to preserve manual configurations:

```bash
echo "network: {config: disabled}" | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

Configure both adapters in Netplan:

```bash
sudo tee /etc/netplan/50-cloud-init.yaml > /dev/null <<EOF
network:
  ethernets:
    enp0s3:
      dhcp4: true
      routes:
        - to: 0.0.0.0/0
          via: 10.0.2.2
          metric: 100
    enp0s8:
      addresses:
        - 192.168.56.102/24
      routes:
        - to: 192.168.56.0/24
  version: 2
EOF
```

Apply the configuration:

```bash
sudo netplan apply
```

Set the hostname:

```bash
sudo hostnamectl set-hostname basevm
```

Test SSH access from the host machine:

```bash
ssh openstack@192.168.56.102
```

If SSH succeeds, the base VM network is correctly configured.

### Add Host Entries

Add hostname-to-IP mappings in `/etc/hosts` for convenient SSH access:

```bash
sudo tee -a /etc/hosts > /dev/null <<EOF
192.168.56.102 basevm
192.168.56.103 keystone
192.168.56.104 glance
192.168.56.105 nova
192.168.56.106 neutron
192.168.56.107 horizon
192.168.56.108 cinder
192.168.56.109 swift
EOF
```

Now you can SSH using hostnames instead of IPs:

```bash
ssh openstack@keystone
```

### Install OpenStack Prerequisites

OpenStack services require several system packages and services.

Add the OpenStack repository for the Caracal release:

```bash
sudo add-apt-repository cloud-archive:caracal
sudo apt update && sudo apt dist-upgrade
```

Install the OpenStack client:

```bash
sudo apt install python3-openstackclient
```

Install memcached for token caching:

```bash
sudo apt install memcached
sudo systemctl enable memcached
sudo systemctl start memcached
```

Install Chrony for time synchronization (critical for distributed services):

```bash
sudo apt install chrony
sudo systemctl enable chronyd
sudo systemctl start chronyd
```

Install MariaDB for database storage:

```bash
sudo apt install mariadb-server python3-pymysql
```

Configure MariaDB for OpenStack by creating `/etc/mysql/mariadb.conf.d/99-openstack.cnf`:

```ini
[mysqld]
bind-address = 0.0.0.0
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
```

Restart MariaDB to apply the configuration:

```bash
sudo systemctl restart mariadb
```

Set up database credentials for the current user:

```bash
CURRENT_USER=$USER
PASSWORD="DBPASS"
sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO '${CURRENT_USER}'@'localhost' IDENTIFIED BY '${PASSWORD}' WITH GRANT OPTION; FLUSH PRIVILEGES;"
```

### Add OpenStack Environment Variables

Add OpenStack client environment variables to `.bashrc`:

```bash
cat <<EOF >> ~/.bashrc
# OpenStack environment variables
export OS_USERNAME=admin
export OS_PASSWORD=DBPASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
EOF
```

Source the updated `.bashrc`:

```bash
source ~/.bashrc
```

### Enable Nested Virtualization (Nova VM Only)

The Nova compute node runs a hypervisor and needs nested virtualization enabled. This configuration happens on the host machine after cloning the Nova VM.

First, power off the Nova VM:

```bash
VBoxManage controlvm "Nova" poweroff
```

Enable hardware virtualization extensions:

```bash
VBoxManage modifyvm "Nova" --hwvirtex on
VBoxManage modifyvm "Nova" --nested-hw-virt on
VBoxManage modifyvm "Nova" --nested-paging on
VBoxManage modifyvm "Nova" --vtx-vpid on
```

Start the VM:

```bash
VBoxManage startvm "Nova" --type headless
```

Inside the Nova VM, verify virtualization support:

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
```

If the output is greater than 0, nested virtualization is enabled.

## What's Next

With the base VM configured, the environment is ready for OpenStack service installation. The next post covers Keystone, the identity service that handles authentication and service discovery for all OpenStack components.

Each subsequent post will:

1. Clone a VM from the base template
2. Configure networking and hostname
3. Install and configure a specific OpenStack service
4. Demonstrate the service in action
5. Cover common troubleshooting scenarios

The series follows the OpenStack installation guide but emphasizes hands-on commands and real output over theory.

## Summary

This post established the foundation for an OpenStack private cloud deployment:

- Installed VirtualBox and created a host-only network
- Built a base Ubuntu Server 24.04.1 LTS VM with dual network adapters
- Installed OpenStack prerequisites (client, memcached, chrony, MariaDB)
- Configured networking for VM-to-VM and host-to-VM communication
- Set up naming conventions and environment variables
- Prepared for service-by-service installation

The base VM serves as a template for all OpenStack services. In the next post, we'll clone this VM and install Keystone, the identity service that authenticates users and services across the OpenStack environment.
