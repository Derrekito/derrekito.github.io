---
title: "OpenStack Nova: Compute Service for Virtual Machine Management"
date: 2026-11-09
categories: [Cloud Computing, Infrastructure]
tags: [openstack, nova, compute, virtualization, kvm, qemu, hypervisor]
---

Nova is OpenStack's compute service, providing the core functionality for launching and managing virtual machine instances. It handles scheduling (deciding which compute node runs an instance), resource allocation, and the complete instance lifecycle from creation to deletion. Nova supports multiple hypervisors including KVM, Xen, VMware, and Hyper-V, offering flexibility in virtualization technologies.

This post covers Nova installation on a dedicated compute node, including hypervisor configuration, database setup, and demonstrates creating flavors and launching instances.

## What Nova Does

Nova orchestrates the entire compute infrastructure:

1. **API Server**: Receives and validates user requests
2. **Scheduler**: Determines which compute host should run an instance based on resources and policies
3. **Conductor**: Mediates interactions between compute nodes and the database
4. **Compute**: Runs on hypervisor hosts, manages instance lifecycle via libvirt/KVM
5. **NoVNC Proxy**: Provides browser-based console access to instances

When a user launches an instance, the request flows through Nova API → Scheduler → Conductor → Compute. The compute service uses Glance to retrieve the image, Neutron to provision networking, and optionally Cinder for persistent storage.

### Nova Cells

Nova uses a "cells" architecture for scalability:

- **Cell0**: Special database for instances that failed to schedule
- **Cell1+**: Normal cells containing compute nodes and instance data

This deployment uses a single cell (cell1) for simplicity. Large deployments partition compute nodes across multiple cells to isolate failure domains.

### Supported Hypervisors

- **KVM/QEMU**: Most common, native Linux virtualization (used in this deployment)
- **Xen**: Paravirtualization and HVM
- **VMware vSphere**: Integration with VMware infrastructure
- **Hyper-V**: Microsoft virtualization
- **LXC**: Container-based virtualization

This deployment uses QEMU (software virtualization) since it runs inside VirtualBox. Production deployments use KVM with hardware virtualization support.

## Prerequisites

Before installing Nova:

- Completed Keystone, RabbitMQ, and Glance installation
- Base VM template with OpenStack prerequisites
- Nested virtualization enabled on the Nova VM (configured in Part 1)

## Cloning the Nova VM

Clone the base VM in VirtualBox:

1. Right-click **BaseVM**
2. Select **Clone**
3. Name: `Nova`
4. MAC Address Policy: **Generate new MAC addresses for all network adapters**
5. Clone type: **Full clone**
6. Click **Clone**

**Important**: Before starting the VM, enable nested virtualization from the host machine:

```bash
VBoxManage controlvm "Nova" poweroff  # If already running
VBoxManage modifyvm "Nova" --hwvirtex on
VBoxManage modifyvm "Nova" --nested-hw-virt on
VBoxManage modifyvm "Nova" --nested-paging on
VBoxManage modifyvm "Nova" --vtx-vpid on
VBoxManage startvm "Nova" --type headless
```

Start the Nova VM and log in.

## Configuring the Nova VM

Update the network configuration:

```bash
# Update Netplan to set static IP to 192.168.56.105
sudo sed -i 's/192\.168\.56\.10[0-9]\/24/192.168.56.105\/24/' /etc/netplan/*

# Update hostname
sudo hostnamectl set-hostname nova

# Apply the configuration
sudo netplan apply
```

Verify nested virtualization support:

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
```

If the output is greater than 0, virtualization extensions are available.

Test SSH from the host:

```bash
ssh openstack@nova
```

## Creating Nova Databases

Nova requires three separate databases:

- **nova_api**: API server metadata
- **nova**: Instance and cell data
- **nova_cell0**: Failed scheduling records

Connect to MariaDB on the Keystone node:

```bash
mysql -h keystone -u root -p
```

In the MariaDB prompt:

```sql
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;

GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY 'NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY 'NOVA_DBPASS';

GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY 'NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY 'NOVA_DBPASS';

GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY 'NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY 'NOVA_DBPASS';

EXIT;
```

Replace `NOVA_DBPASS` with a secure password.

## Creating the Nova User in Keystone

Create the Nova service user:

```bash
openstack user create --domain default --password NOVA_DBPASS nova
```

Output:

```
+---------------------+----------------------------------+
| Field               | Value                            |
+---------------------+----------------------------------+
| domain_id           | default                          |
| enabled             | True                             |
| id                  | 3df5b0fc0dbc4488b17c7927eab88462 |
| name                | nova                             |
| options             | {}                               |
| password_expires_at | None                             |
+---------------------+----------------------------------+
```

Add the `admin` role:

```bash
openstack role add --project service --user nova admin
```

## Registering Nova in the Service Catalog

Create the compute service:

```bash
openstack service create --name nova --description "OpenStack Compute" compute
```

Output:

```
+-------------+----------------------------------+
| Field       | Value                            |
+-------------+----------------------------------+
| description | OpenStack Compute                |
| enabled     | True                             |
| id          | 976bf07ff30a45a5b332b4cfbffba5fa |
| name        | nova                             |
| type        | compute                          |
+-------------+----------------------------------+
```

Create the endpoints:

```bash
openstack endpoint create --region RegionOne compute public http://nova:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://nova:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://nova:8774/v2.1
```

Each endpoint command outputs:

```
+--------------+----------------------------------+
| Field        | Value                            |
+--------------+----------------------------------+
| enabled      | True                             |
| id           | ca296e9525df44d5ba8ce1b07970f949 |
| interface    | public                           |
| region       | RegionOne                        |
| service_id   | 976bf07ff30a45a5b332b4cfbffba5fa |
| service_name | nova                             |
| service_type | compute                          |
| url          | http://nova:8774/v2.1            |
+--------------+----------------------------------+
```

## Installing Nova

Install all Nova components (API, scheduler, conductor, compute, and console proxy):

```bash
sudo apt install -y nova-api nova-conductor nova-novncproxy nova-scheduler nova-compute
```

This installs the complete Nova stack on a single node. Production deployments typically separate the controller components (API, scheduler, conductor) from compute nodes.

## Configuring Nova

Edit `/etc/nova/nova.conf` with the following sections:

### Default Configuration

```ini
[DEFAULT]
log_dir = /var/log/nova
lock_path = /var/lock/nova
state_path = /var/lib/nova
transport_url = rabbit://openstack:RABBITMQ_PASS@keystone:5672/
enabled_apis = osapi_compute,metadata
metadata_listen = 0.0.0.0
metadata_listen_port = 8775
compute_driver = libvirt.LibvirtDriver
```

### API Authentication

```ini
[api]
auth_strategy = keystone
```

### Keystone Authentication Token

```ini
[keystone_authtoken]
www_authenticate_uri = http://keystone:5000
auth_url = http://keystone:5000/v3
memcached_servers = keystone:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = NOVA_DBPASS
```

### RabbitMQ Configuration

```ini
[oslo_messaging_rabbit]
rabbit_host = keystone
rabbit_port = 5672
rabbit_userid = openstack
rabbit_password = RABBITMQ_PASS
rabbit_virtual_host = /
rabbit_retry_interval = 1
rabbit_retry_backoff = 2
rabbit_max_retries = 0
```

### Database Connections

```ini
[api_database]
connection = mysql+pymysql://nova:NOVA_DBPASS@keystone/nova_api

[database]
connection = mysql+pymysql://nova:NOVA_DBPASS@keystone/nova
```

### Glance Integration

```ini
[glance]
api_servers = http://glance:9292
```

### Placement Integration

```ini
[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://keystone:5000/v3
username = placement
password = PLACEMENT_DBPASS
```

The Placement service (covered in the next post) tracks resource inventory.

### Neutron Integration

```ini
[neutron]
auth_url = http://keystone:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = neutron
password = NEUTRON_DBPASS
service_metadata_proxy = true
metadata_proxy_shared_secret = 64d7e168c8cd214b5f91
```

### Concurrency Configuration

```ini
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
```

### Libvirt Hypervisor

```ini
[libvirt]
virt_type = qemu
```

Set `virt_type` to `qemu` for software virtualization. Production systems with hardware virtualization use `kvm`.

## Fixing Eventlet Monkey-Patching

Nova's database migration tools require eventlet monkey-patching. Edit the following files to add the patch at the top of each script:

- `/usr/bin/nova-manage`
- `/usr/bin/nova-scheduler`
- `/usr/bin/nova-conductor`

Add these lines after the shebang:

```python
#!/usr/bin/python3
# PBR Generated from 'console_scripts'
import eventlet
eventlet.monkey_patch()

import sys
# ... rest of file
```

This prevents "RLock not greened" warnings during database operations.

## Initializing Nova Databases

Populate the nova_api database:

```bash
sudo -u nova nova-manage api_db sync
```

Register the cell0 database:

```bash
sudo -u nova nova-manage cell_v2 map_cell0
```

Output:

```
Cell0 is already setup
```

Create the cell1 cell:

```bash
sudo -u nova nova-manage cell_v2 create_cell --name=cell1 --verbose
```

Output:

```
--transport-url not provided in the command line, using the value [DEFAULT]/transport_url from the configuration file
--database_connection not provided in the command line, using the value [database]/connection from the configuration file
6ecc53ec-cc8f-42ec-bafe-f374ae5f1943
```

The UUID identifies the cell.

Populate the nova database:

```bash
sudo -u nova nova-manage db sync
```

Verify cells are configured:

```bash
sudo -u nova nova-manage cell_v2 list_cells
```

Output:

```
+-------+--------------------------------------+---------------+-----------------------------------------------+----------+
|  Name |                 UUID                 | Transport URL |              Database Connection              | Disabled |
+-------+--------------------------------------+---------------+-----------------------------------------------+----------+
| cell0 | 00000000-0000-0000-0000-000000000000 |     none:/    | mysql+pymysql://nova:****@keystone/nova_cell0 |  False   |
| cell1 | 6ecc53ec-cc8f-42ec-bafe-f374ae5f1943 |    rabbit:    |    mysql+pymysql://nova:****@keystone/nova    |  False   |
+-------+--------------------------------------+---------------+-----------------------------------------------+----------+
```

Both cells should be present and enabled.

## Starting Nova Services

Restart all Nova services:

```bash
sudo systemctl restart nova-api nova-scheduler nova-conductor nova-novncproxy nova-compute
```

Enable services to start on boot:

```bash
sudo systemctl enable nova-api nova-scheduler nova-conductor nova-novncproxy nova-compute
```

Verify services are running:

```bash
openstack compute service list
```

Output:

```
+--------------------------------------+----------------+------+----------+--------+-------+----------------------------+
| ID                                   | Binary         | Host | Zone     | Status | State | Updated At                 |
+--------------------------------------+----------------+------+----------+--------+-------+----------------------------+
| 8920495c-530f-4242-854a-13e97e9fac2b | nova-scheduler | nova | internal | enabled | up   | 2025-02-03T18:56:55.000000 |
| ec6c9070-d3e6-48b8-92db-5156d4a877b1 | nova-conductor | nova | internal | enabled | up   | 2025-02-03T18:56:55.000000 |
| 5aee789f-4bc0-4935-9655-a2f78238c31e | nova-compute   | nova | nova     | enabled | up   | 2025-02-03T18:56:56.000000 |
+--------------------------------------+----------------+------+----------+--------+-------+----------------------------+
```

All services should show `State: up`.

## Creating SSH Keypairs

Instances require SSH keypairs for authentication. Generate a keypair:

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
```

Output:

```
Generating public/private rsa key pair.
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
Your identification has been saved in /home/openstack/.ssh/id_rsa
Your public key has been saved in /home/openstack/.ssh/id_rsa.pub
```

Upload the public key to OpenStack:

```bash
openstack keypair create mykey --public-key ~/.ssh/id_rsa.pub
```

Output:

```
+-------------+-------------------------------------------------+
| Field       | Value                                           |
+-------------+-------------------------------------------------+
| created_at  | None                                            |
| fingerprint | 7a:5b:5b:30:fd:39:8a:a0:88:c8:17:de:3f:73:fd:13 |
| id          | mykey                                           |
| name        | mykey                                           |
| type        | ssh                                             |
| user_id     | 3df5b0fc0dbc4488b17c7927eab88462                |
+-------------+-------------------------------------------------+
```

Alternatively, create a keypair directly in OpenStack:

```bash
openstack keypair create my-key > my-key.pem
chmod 600 my-key.pem
```

List keypairs:

```bash
openstack keypair list
```

Output:

```
+--------+-------------------------------------------------+------+
| Name   | Fingerprint                                     | Type |
+--------+-------------------------------------------------+------+
| my-key | 91:2d:a0:56:a7:04:d6:ce:98:f7:c8:79:d8:94:de:61 | ssh  |
| mykey  | 7a:5b:5b:30:fd:39:8a:a0:88:c8:17:de:3f:73:fd:13 | ssh  |
+--------+-------------------------------------------------+------+
```

## Creating Flavors

Flavors define instance sizes (CPU, RAM, disk). Create a "small" flavor:

```bash
openstack flavor create --ram 2048 --disk 20 --vcpus 1 small
```

Output:

```
+----------------------------+--------------------------------------+
| Field                      | Value                                |
+----------------------------+--------------------------------------+
| OS-FLV-DISABLED:disabled   | False                                |
| OS-FLV-EXT-DATA:ephemeral  | 0                                    |
| disk                       | 20                                   |
| id                         | 36c8a22b-0fc7-4325-90f5-a1800b4312c5 |
| name                       | small                                |
| os-flavor-access:is_public | True                                 |
| ram                        | 2048                                 |
| vcpus                      | 1                                    |
+----------------------------+--------------------------------------+
```

List flavors:

```bash
openstack flavor list
```

Output:

```
+--------------------------------------+-------+------+------+-----------+-------+-----------+
| ID                                   | Name  |  RAM | Disk | Ephemeral | VCPUs | Is Public |
+--------------------------------------+-------+------+------+-----------+-------+-----------+
| 36c8a22b-0fc7-4325-90f5-a1800b4312c5 | small | 2048 |   20 |         0 |     1 | True      |
+--------------------------------------+-------+------+------+-----------+-------+-----------+
```

## Launching an Instance (Preview)

Once Neutron is configured (next few posts), launch instances:

```bash
openstack server create --flavor small \
  --image "Ubuntu 22.04" \
  --network provider \
  --security-group default \
  --key-name my-key \
  test-instance
```

This command creates an instance using:
- Flavor: `small` (1 vCPU, 2048 MB RAM, 20 GB disk)
- Image: Ubuntu 22.04 from Glance
- Network: `provider` (requires Neutron configuration)
- Security group: `default` (firewall rules)
- SSH key: `my-key`

The instance transitions through states: `BUILD` → `ACTIVE`.

## Common Issues and Troubleshooting

### Services Show "State: down"

If `openstack compute service list` shows services as `down`:

1. **Check service logs**:
   ```bash
   sudo journalctl -u nova-compute -n 50
   sudo journalctl -u nova-scheduler -n 50
   ```

2. **Verify RabbitMQ connection**:
   ```bash
   sudo rabbitmqctl list_connections
   ```

3. **Restart services**:
   ```bash
   sudo systemctl restart nova-api nova-scheduler nova-conductor nova-compute
   ```

### Disk Space Exhausted

Nova compute nodes require significant disk space for instances. Check disk usage:

```bash
df -h
```

If `/` is full, extend the logical volume:

```bash
sudo vgdisplay ubuntu-vg  # Check free space
sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
```

### Database Connection Failures

If Nova can't connect to the database:

- Verify credentials in `/etc/nova/nova.conf`
- Test database connection:
  ```bash
  mysql -h keystone -u nova -p nova
  ```
- Check MariaDB is listening on `0.0.0.0`: `sudo ss -tulnp | grep 3306`

### Placement API Errors

Nova requires Placement (covered in the next post). If you see Placement-related errors:

- Ensure Placement is installed and registered
- Verify the `[placement]` section in `/etc/nova/nova.conf`
- Check Placement endpoint: `openstack endpoint list | grep placement`

### Eventlet RLock Warnings

If you see "RLock not greened" warnings:

- Apply the monkey-patch fix to `/usr/bin/nova-manage` and other scripts (shown earlier)
- Restart Nova services

## What's Next

With Nova installed, the compute infrastructure is ready. However, Nova requires Placement for resource tracking. The next post covers Placement installation and configuration, which completes Nova's resource management capabilities.

## Summary

This post covered:

- Cloning the Nova VM and enabling nested virtualization
- Creating three Nova databases (nova_api, nova, nova_cell0)
- Creating the Nova service user in Keystone
- Registering Nova in the service catalog
- Installing all Nova components
- Configuring Nova with database, RabbitMQ, Glance, and Neutron integration
- Fixing eventlet monkey-patching for database tools
- Initializing databases and configuring cells
- Verifying Nova services are running
- Creating SSH keypairs and flavors
- Troubleshooting common Nova issues

Nova is now managing the compute infrastructure. In the next post, we'll install Placement to track resource inventory and enable instance scheduling.
