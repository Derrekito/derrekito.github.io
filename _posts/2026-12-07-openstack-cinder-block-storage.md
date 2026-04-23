---
title: "OpenStack Cinder: Block Storage Service for Persistent Volumes"
date: 2026-12-07
categories: [Cloud Computing, Infrastructure]
tags: [openstack, cinder, block-storage, lvm, iscsi, volumes, persistent-storage]
---

Cinder provides block storage services for OpenStack, enabling instances to use persistent volumes that survive instance termination. Unlike ephemeral instance storage (which disappears when an instance is deleted), Cinder volumes persist independently and can be attached to different instances over time. This makes Cinder essential for databases, stateful applications, and any workload requiring durable storage.

This post covers Cinder installation with a controller node on Keystone and a storage node on a dedicated VM, LVM configuration for volume backend, and demonstrates creating and managing volumes.

## What Cinder Does

Cinder manages the lifecycle of block storage volumes:

1. **Volume Creation**: Allocate storage from a backend pool
2. **Volume Attachment**: Attach volumes to instances as block devices (e.g., `/dev/vdb`)
3. **Volume Detachment**: Detach volumes without data loss
4. **Volume Snapshots**: Create point-in-time copies of volumes
5. **Volume Backups**: Archive volumes to object storage (Swift, S3)
6. **Volume Cloning**: Create new volumes from existing volumes or snapshots
7. **Volume Migration**: Move volumes between storage backends
8. **Volume Encryption**: Transparent encryption for data at rest

Cinder abstracts the underlying storage technology, supporting multiple backends through a plugin architecture.

### Cinder Architecture

Cinder consists of several components:

- **cinder-api**: Receives and validates volume requests
- **cinder-scheduler**: Selects which storage backend should provide a volume
- **cinder-volume**: Manages volume creation, deletion, and attachment on storage nodes
- **cinder-backup** (optional): Handles volume backups to object storage

### Storage Backends

Cinder supports numerous storage backends:

- **LVM**: Logical Volume Manager (used in this deployment)
- **Ceph**: Distributed block storage
- **NetApp**: Enterprise storage arrays
- **EMC**: VMAX, VNX, XtremIO
- **NFS**: Network File System
- **GlusterFS**: Distributed file system
- **iSCSI**: Internet Small Computer Systems Interface

This deployment uses LVM with iSCSI for simplicity. Production deployments often use enterprise storage or Ceph for high availability and performance.

### Volume Attachment Process

When an instance requests a volume:

1. Cinder scheduler selects a storage backend with available capacity
2. Cinder volume service creates the volume (LVM logical volume)
3. Cinder exposes the volume via iSCSI target
4. Nova compute connects to the iSCSI target
5. Nova attaches the volume to the instance as a block device
6. The instance sees a new disk (e.g., `/dev/vdb`)

The instance can then format, mount, and use the volume like any physical disk.

## Prerequisites

Before installing Cinder:

- Keystone, RabbitMQ, and Nova operational
- Base VM template available
- Additional disk space for volume storage (either add a second virtual disk or extend the existing disk)

## Installing Cinder Controller on Keystone Node

Cinder's API and scheduler run on the controller (Keystone node). SSH to the Keystone VM:

```bash
ssh openstack@keystone
```

### Creating the Cinder Database

Create the Cinder database:

```bash
sudo mysql -u root -p
```

In the MariaDB prompt:

```sql
CREATE DATABASE cinder;

GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY 'CINDER_DBPASS';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY 'CINDER_DBPASS';

EXIT;
```

### Creating the Cinder User in Keystone

Create the Cinder service user:

```bash
openstack user create --domain default --password-prompt cinder
```

Add the admin role:

```bash
openstack role add --project service --user cinder admin
```

### Registering Cinder Services

Create the block storage services (v3 API):

```bash
openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3
```

Output:

```
+-------------+----------------------------------+
| Field       | Value                            |
+-------------+----------------------------------+
| description | OpenStack Block Storage          |
| enabled     | True                             |
| id          | ab3bbbef8b7f4b8c9de8ff5e4e3f3c51 |
| name        | cinderv3                         |
| type        | volumev3                         |
+-------------+----------------------------------+
```

Create the endpoints:

```bash
openstack endpoint create --region RegionOne volumev3 public http://keystone:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 internal http://keystone:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 admin http://keystone:8776/v3/%\(project_id\)s
```

The `%(project_id)s` placeholder is substituted with the user's project ID at runtime.

### Installing Cinder Controller Packages

Install the API and scheduler:

```bash
sudo apt install -y cinder-api cinder-scheduler
```

### Configuring Cinder Controller

Edit `/etc/cinder/cinder.conf`:

```bash
sudo nano /etc/cinder/cinder.conf
```

**[database] Section**:

```ini
[database]
connection = mysql+pymysql://cinder:CINDER_DBPASS@keystone/cinder
```

**[DEFAULT] Section**:

```ini
[DEFAULT]
transport_url = rabbit://openstack:RABBITMQ_PASS@keystone
auth_strategy = keystone
my_ip = 192.168.56.103
```

Set `my_ip` to the controller's management IP.

**[keystone_authtoken] Section**:

```ini
[keystone_authtoken]
www_authenticate_uri = http://keystone:5000
auth_url = http://keystone:5000
memcached_servers = keystone:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = CINDER_DBPASS
```

**[oslo_concurrency] Section**:

```ini
[oslo_concurrency]
lock_path = /var/lib/cinder/tmp
```

### Initializing the Cinder Database

Populate the database:

```bash
sudo su -s /bin/sh -c "cinder-manage db sync" cinder
```

### Configuring Nova for Cinder

Edit `/etc/nova/nova.conf` on the Nova node to integrate with Cinder:

```ini
[cinder]
os_region_name = RegionOne
```

Restart Nova API:

```bash
sudo systemctl restart nova-api
```

### Starting Cinder Controller Services

Restart Cinder services on the Keystone node:

```bash
sudo systemctl restart cinder-scheduler apache2
```

Enable services:

```bash
sudo systemctl enable cinder-scheduler
```

Verify services are running:

```bash
sudo systemctl status cinder-scheduler
```

## Cloning the Cinder Storage Node VM

Clone the base VM for the storage node:

1. Right-click **BaseVM**
2. Select **Clone**
3. Name: `Cinder`
4. MAC Address Policy: **Generate new MAC addresses**
5. Clone type: **Full clone**
6. Click **Clone**

**Important**: Before starting, add a second virtual disk for volume storage:

1. Select the Cinder VM in VirtualBox
2. Go to **Settings → Storage**
3. Click the **Add Hard Disk** icon
4. Create a new disk (e.g., 25 GB, dynamically allocated)
5. Click **OK**

Start the Cinder VM and log in.

## Configuring the Cinder Storage Node

Update network configuration:

```bash
# Update Netplan to set static IP to 192.168.56.108
sudo sed -i 's/192\.168\.56\.10[0-9]\/24/192.168.56.108\/24/' /etc/netplan/*

# Update hostname
sudo hostnamectl set-hostname cinder

# Apply configuration
sudo netplan apply
```

### Setting Up LVM for Volume Storage

Install LVM tools:

```bash
sudo apt install -y lvm2 thin-provisioning-tools
```

Identify the second disk:

```bash
lsblk
```

Output:

```
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sda      8:0    0   25G  0 disk
├─sda1   8:1    0    1M  0 part
├─sda2   8:2    0    2G  0 part /boot
└─sda3   8:3    0   23G  0 part
  └─...               ... ...  /
sdb      8:16   0   25G  0 disk
```

The second disk is `/dev/sdb`. Create a physical volume:

```bash
sudo pvcreate /dev/sdb
```

Create a volume group:

```bash
sudo vgcreate cinder-volumes /dev/sdb
```

Verify the volume group:

```bash
sudo vgdisplay cinder-volumes
```

Output:

```
--- Volume group ---
VG Name               cinder-volumes
VG Size               <25.00 GiB
PE Size               4.00 MiB
Total PE              6399
Free  PE / Size       6399 / <25.00 GiB
```

### Configuring LVM Filter

Edit `/etc/lvm/lvm.conf` to prevent LVM from scanning instance volumes:

```bash
sudo nano /etc/lvm/lvm.conf
```

Find the `devices` section and set the filter:

```
devices {
    # Accept only /dev/sdb, reject everything else
    filter = [ "a/sdb/", "r/.*/"]
}
```

This ensures LVM only uses `/dev/sdb` for Cinder volumes.

### Installing Cinder Volume Service

Install the volume service and iSCSI target daemon:

```bash
sudo apt install -y cinder-volume tgt
```

### Configuring Cinder Volume Service

Edit `/etc/cinder/cinder.conf`:

```bash
sudo nano /etc/cinder/cinder.conf
```

**[database] Section**:

```ini
[database]
connection = mysql+pymysql://cinder:CINDER_DBPASS@keystone/cinder
```

**[DEFAULT] Section**:

```ini
[DEFAULT]
transport_url = rabbit://openstack:RABBITMQ_PASS@keystone
auth_strategy = keystone
my_ip = 192.168.56.108
enabled_backends = lvm
glance_api_servers = http://glance:9292
```

Set `my_ip` to the storage node's IP.

**[keystone_authtoken] Section**:

```ini
[keystone_authtoken]
www_authenticate_uri = http://keystone:5000
auth_url = http://keystone:5000
memcached_servers = keystone:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = CINDER_DBPASS
```

**[lvm] Section** (backend configuration):

```ini
[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = cinder-volumes
target_protocol = iscsi
target_helper = tgtadm
```

**[oslo_concurrency] Section**:

```ini
[oslo_concurrency]
lock_path = /var/lib/cinder/tmp
```

### Starting Cinder Volume Services

Restart services:

```bash
sudo systemctl restart tgt cinder-volume
```

Enable services:

```bash
sudo systemctl enable tgt cinder-volume
```

Verify services are running:

```bash
sudo systemctl status cinder-volume
sudo systemctl status tgt
```

## Verifying Cinder Operation

Check Cinder services are operational:

```bash
openstack volume service list
```

Output:

```
+------------------+-------------------+------+---------+-------+----------------------------+
| Binary           | Host              | Zone | Status  | State | Updated At                 |
+------------------+-------------------+------+---------+-------+----------------------------+
| cinder-scheduler | keystone          | nova | enabled | up    | 2026-12-07T12:34:56.000000 |
| cinder-volume    | cinder@lvm        | nova | enabled | up    | 2026-12-07T12:34:58.000000 |
+------------------+-------------------+------+---------+-------+----------------------------+
```

Both services should show `State: up`.

## Creating and Managing Volumes

### Create a Volume

Create a 10 GB volume:

```bash
openstack volume create --size 10 test-volume
```

Output:

```
+---------------------+--------------------------------------+
| Field               | Value                                |
+---------------------+--------------------------------------+
| attachments         | []                                   |
| availability_zone   | nova                                 |
| created_at          | 2026-12-07T12:35:10.000000           |
| id                  | 573e024d-5235-49ce-8332-be1576d323f8 |
| name                | test-volume                          |
| size                | 10                                   |
| status              | creating                             |
| volume_type         | __DEFAULT__                          |
+---------------------+--------------------------------------+
```

The volume status transitions from `creating` to `available`.

### List Volumes

```bash
openstack volume list
```

Output:

```
+--------------------------------------+-------------+-----------+------+-------------+
| ID                                   | Name        | Status    | Size | Attached to |
+--------------------------------------+-------------+-----------+------+-------------+
| 573e024d-5235-49ce-8332-be1576d323f8 | test-volume | available |   10 |             |
+--------------------------------------+-------------+-----------+------+-------------+
```

### Attach a Volume to an Instance

Attach the volume to a running instance:

```bash
openstack server add volume <instance-name> test-volume
```

The volume appears as a block device in the instance (e.g., `/dev/vdb`).

### Detach a Volume

```bash
openstack server remove volume <instance-name> test-volume
```

The volume returns to `available` status and can be attached to another instance.

### Delete a Volume

```bash
openstack volume delete test-volume
```

The volume is removed and storage is reclaimed.

## Common Issues and Troubleshooting

### Cinder-Volume Service Shows Down

If `openstack volume service list` shows cinder-volume as `down`:

1. **Check service status**:
   ```bash
   sudo systemctl status cinder-volume
   ```

2. **Check logs**:
   ```bash
   sudo journalctl -u cinder-volume -n 50
   sudo tail -f /var/log/cinder/cinder-volume.log
   ```

3. **Verify LVM volume group exists**:
   ```bash
   sudo vgdisplay cinder-volumes
   ```

4. **Restart services**:
   ```bash
   sudo systemctl restart tgt cinder-volume
   ```

### Volume Creation Fails

If volume creation fails with "No valid backend":

1. **Verify cinder-volume is running** and shows `State: up`

2. **Check enabled backends** in `/etc/cinder/cinder.conf`:
   ```ini
   enabled_backends = lvm
   ```

3. **Verify LVM volume group has free space**:
   ```bash
   sudo vgdisplay cinder-volumes
   ```

4. **Check scheduler logs**:
   ```bash
   sudo tail -f /var/log/cinder/cinder-scheduler.log
   ```

### iSCSI Attachment Failures

If volumes can't attach to instances:

1. **Verify tgt service is running**:
   ```bash
   sudo systemctl status tgt
   ```

2. **Check iSCSI targets**:
   ```bash
   sudo tgtadm --lld iscsi --op show --mode target
   ```

3. **Verify network connectivity** between Nova and Cinder nodes:
   ```bash
   ping cinder
   ```

4. **Check Nova compute logs**:
   ```bash
   sudo journalctl -u nova-compute -n 50
   ```

### LVM Scanning Instance Volumes

If LVM incorrectly scans instance volumes:

- Verify the filter in `/etc/lvm/lvm.conf`:
  ```
  filter = [ "a/sdb/", "r/.*/"]
  ```

- Rebuild LVM cache:
  ```bash
  sudo pvscan --cache
  ```

## Volume Types and QoS (Advanced)

Cinder supports volume types for different storage tiers:

```bash
openstack volume type create ssd
openstack volume type create hdd
```

Associate backend with volume type:

```bash
openstack volume type set ssd --property volume_backend_name=lvm-ssd
```

Create volume with specific type:

```bash
openstack volume create --type ssd --size 20 fast-volume
```

## What's Next

With Cinder operational, instances can use persistent block storage. The next post covers Swift, the object storage service for storing unstructured data like images, backups, and archives.

## Summary

This post covered:

- Cinder's role in providing persistent block storage
- Architecture with controller and storage nodes
- Storage backends and LVM with iSCSI
- Installing Cinder controller on Keystone node
- Creating the Cinder database and service user
- Registering Cinder services and endpoints
- Configuring Cinder API and scheduler
- Cloning the Cinder storage node VM
- Adding a second virtual disk for volume storage
- Setting up LVM physical volumes and volume groups
- Configuring LVM filters to prevent instance volume scanning
- Installing cinder-volume and tgt (iSCSI target)
- Configuring the LVM backend driver
- Verifying Cinder services are operational
- Creating, listing, attaching, and deleting volumes
- Troubleshooting service failures, volume creation, and iSCSI issues

Cinder is now providing persistent block storage for instances. In the next post, we'll install Swift to provide object storage for unstructured data.
