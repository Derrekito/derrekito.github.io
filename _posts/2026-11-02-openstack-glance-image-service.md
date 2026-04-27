---
title: "OpenStack Glance: Image Service for Virtual Machine Templates"
date: 2026-11-02
categories: [Cloud Computing, Infrastructure]
tags: [openstack, glance, images, qcow2, vm-templates, storage]
---

Glance provides image services for OpenStack, managing virtual machine disk images that Nova uses to launch instances. It acts as a centralized image repository, allowing users to discover, register, and retrieve images. Glance supports multiple image formats including raw, VHD, VMDK, and QCOW2, enabling compatibility with various virtualization platforms.

This post covers Glance installation on a dedicated VM, configuration for Keystone authentication, and demonstrates uploading and managing images.

## What Glance Does

Glance serves two primary functions:

1. **Image Storage**: Stores VM disk images in various backends (local filesystem, Swift, Ceph, etc.)
2. **Image Metadata**: Tracks image properties like format, size, checksum, and visibility

When Nova launches an instance, it retrieves the image from Glance, copies it to the compute node, and boots from it. Glance ensures images are available across all compute nodes without manual copying.

### Image Properties

Each image in Glance has metadata:

- **Format**: Disk format (qcow2, raw, vmdk, vhd, iso)
- **Container format**: Typically `bare` (no container) or `ovf`
- **Visibility**: Public (all users), private (owner only), shared, or community
- **Status**: Queued, saving, active, deactivated, deleted
- **Size**: Image file size in bytes
- **Checksum**: MD5 or SHA256 hash for integrity verification
- **Min disk/RAM**: Minimum resources required to boot the image

Glance also supports custom properties for specific use cases (e.g., `hw_disk_bus=scsi` for SCSI disk controllers).

### Supported Image Formats

- **QCOW2**: QEMU Copy-On-Write version 2, supports compression and snapshots (most common)
- **Raw**: Unformatted disk image (larger but fastest)
- **VHD**: Virtual Hard Disk (Hyper-V)
- **VMDK**: Virtual Machine Disk (VMware)
- **ISO**: Optical disc image (for installation media)

This deployment uses QCOW2 for space efficiency and snapshot support.

## Prerequisites

Before installing Glance:

- Completed Keystone installation (Part 2)
- RabbitMQ running on Keystone node (Part 3)
- Base VM template with OpenStack prerequisites

## Cloning the Glance VM

Clone the base VM in VirtualBox:

1. Right-click **BaseVM**
2. Select **Clone**
3. Name: `Glance`
4. MAC Address Policy: **Generate new MAC addresses for all network adapters**
5. Clone type: **Full clone**
6. Click **Clone**

Start the Glance VM and log in.

## Configuring the Glance VM

Update the network configuration for the Glance-specific IP:

```bash
# Update Netplan to set static IP to 192.168.56.104
sudo sed -i 's/192\.168\.56\.10[0-9]\/24/192.168.56.104\/24/' /etc/netplan/*

# Update hostname
sudo hostnamectl set-hostname glance

# Apply the configuration (or reboot if SSH'd in)
sudo netplan apply
```

Verify the network configuration:

```bash
ip addr show enp0s8
```

Expected output should show `192.168.56.104/24`.

Test SSH from the host:

```bash
ssh openstack@glance
```

## Creating the Glance Database

Connect to MariaDB on the Keystone node (or create the database remotely):

```bash
# Connect to MariaDB (from Glance VM, connecting to Keystone's MariaDB)
mysql -h keystone -u root -p
```

In the MariaDB prompt:

```sql
CREATE DATABASE glance;

GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'GLANCE_DBPASS';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'GLANCE_DBPASS';

EXIT;
```

Replace `GLANCE_DBPASS` with a secure password.

Verify the database was created:

```bash
mysql -h keystone -u glance -p -e "SHOW DATABASES;"
```

You should see `glance` in the list.

## Creating the Glance User in Keystone

Glance needs a service user in Keystone for authentication. From the Glance VM (or Keystone VM), create the user:

```bash
openstack user create --domain default --password-prompt glance
```

Enter the password when prompted (use `GLANCE_PASS` or similar).

Output:

```
+---------------------+----------------------------------+
| Field               | Value                            |
+---------------------+----------------------------------+
| domain_id           | default                          |
| enabled             | True                             |
| id                  | 5aeaa7abc8e24c9fbd59392904d8af7d |
| name                | glance                           |
| options             | {}                               |
| password_expires_at | None                             |
+---------------------+----------------------------------+
```

Add the `admin` role to the `glance` user in the `service` project:

```bash
openstack role add --project service --user glance admin
```

This command produces no output on success.

Verify the user was created:

```bash
openstack user list
```

Output:

```
+----------------------------------+--------+
| ID                               | Name   |
+----------------------------------+--------+
| 24c7f0759f514d3f8a777f4f032cf4f6 | admin  |
| e32b40b0f63f4afa951e615878462a93 | demo   |
| 5aeaa7abc8e24c9fbd59392904d8af7d | glance |
+----------------------------------+--------+
```

## Registering Glance in the Service Catalog

Register the Glance service in Keystone:

```bash
openstack service create --name glance --description "OpenStack Image" image
```

Output:

```
+-------------+----------------------------------+
| Field       | Value                            |
+-------------+----------------------------------+
| description | OpenStack Image                  |
| enabled     | True                             |
| id          | 6451af5b580e4a28814ba7bbf92230df |
| name        | glance                           |
| type        | image                            |
+-------------+----------------------------------+
```

Create the three endpoints (public, internal, admin) for Glance:

```bash
openstack endpoint create --region RegionOne image public http://controller:9292
openstack endpoint create --region RegionOne image internal http://controller:9292
openstack endpoint create --region RegionOne image admin http://controller:9292
```

Each command outputs endpoint details:

```
+--------------+----------------------------------+
| Field        | Value                            |
+--------------+----------------------------------+
| enabled      | True                             |
| id           | 9e9ee68750574634812acfd1fb60141d |
| interface    | public                           |
| region       | RegionOne                        |
| region_id    | RegionOne                        |
| service_id   | 6451af5b580e4a28814ba7bbf92230df |
| service_name | glance                           |
| service_type | image                            |
| url          | http://controller:9292           |
+--------------+----------------------------------+
```

The `controller` hostname should resolve to the Glance VM's IP (or you can use the IP directly).

## Installing Glance

Install the Glance package:

```bash
sudo apt install -y glance
```

This installs `glance-api` and its dependencies.

## Configuring Glance

Edit the Glance API configuration file at `/etc/glance/glance-api.conf`.

### Database Connection

Find the `[database]` section and set the connection string:

```ini
[database]
connection = mysql+pymysql://glance:GLANCE_DBPASS@keystone/glance
```

Replace `GLANCE_DBPASS` with the database password set earlier. The hostname `keystone` resolves to the MariaDB server.

### Keystone Authentication

Add Keystone authentication configuration to `/etc/glance/glance-api.conf`:

```bash
sudo tee -a /etc/glance/glance-api.conf << EOF

[keystone_authtoken]
www_authenticate_uri = http://keystone:5000
auth_url = http://keystone:5000
memcached_servers = keystone:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = GLANCE_PASS

[paste_deploy]
flavor = keystone
EOF
```

Replace `GLANCE_PASS` with the Glance user password.

The `[keystone_authtoken]` section tells Glance how to authenticate with Keystone. The `[paste_deploy]` section enables Keystone authentication middleware.

### Bind to All Interfaces

By default, Glance listens only on localhost. Configure it to accept remote connections:

```bash
sudo sed -i '/\[DEFAULT\]/a bind_host = 0.0.0.0' /etc/glance/glance-api.conf
```

This adds `bind_host = 0.0.0.0` under the `[DEFAULT]` section.

## Initializing the Glance Database

Populate the Glance database schema:

```bash
sudo glance-manage db_sync
```

Output shows database migrations running:

```
2025-01-27 01:33:30.061 3985 INFO alembic.runtime.migration [-] Context impl MySQLImpl.
2025-01-27 01:33:30.062 3985 INFO alembic.runtime.migration [-] Will assume non-transactional DDL.
...
2025-01-27 01:33:40.182 3985 INFO alembic.runtime.migration [-] Running upgrade  -> liberty, liberty initial
2025-01-27 01:33:37.724 3985 INFO alembic.runtime.migration [-] Running upgrade liberty -> mitaka01, add index on created_at and updated_at columns of 'images' table
...
Database is synced successfully.
```

The migrations create tables for images, image members, and metadata.

## Starting the Glance Service

Restart Glance to apply the configuration:

```bash
sudo systemctl restart glance-api
```

Enable Glance to start on boot:

```bash
sudo systemctl enable glance-api
```

Verify Glance is running:

```bash
sudo systemctl status glance-api
```

Expected output:

```
● glance-api.service - OpenStack Image Service (API)
   Loaded: loaded (/lib/systemd/system/glance-api.service; enabled)
   Active: active (running)
```

Check Glance is listening on port 9292:

```bash
sudo ss -tulnp | grep 9292
```

Output:

```
tcp   LISTEN 0  128  0.0.0.0:9292  0.0.0.0:*  users:(("glance-api",pid=5678,...))
```

## Verifying Service Catalog Registration

Check the service catalog to confirm Glance is registered:

```bash
openstack catalog list
```

Output:

```
+-----------+-----------+-----------------------------------------+
| Name      | Type      | Endpoints                               |
+-----------+-----------+-----------------------------------------+
| keystone  | identity  | RegionOne                               |
|           |           |   public: http://controller:5000/v3/    |
|           |           |   internal: http://controller:5000/v3/  |
|           |           |   admin: http://controller:5000/v3/     |
|           |           |                                         |
| glance    | image     | RegionOne                               |
|           |           |   public: http://controller:9292        |
|           |           |   internal: http://controller:9292      |
|           |           |   admin: http://controller:9292         |
+-----------+-----------+-----------------------------------------+
```

## Uploading Images to Glance

With Glance operational, upload VM images for instance creation.

### Download CirrOS Test Image

CirrOS is a minimal Linux distribution designed for testing cloud deployments. Download the latest image:

```bash
wget http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img
```

Upload the image to Glance:

```bash
openstack image create "cirros" \
  --file cirros-0.6.2-x86_64-disk.img \
  --disk-format qcow2 \
  --container-format bare \
  --public
```

Output:

```
+------------------+------------------------------------------------------+
| Field            | Value                                                |
+------------------+------------------------------------------------------+
| container_format | bare                                                 |
| created_at       | 2025-01-27T01:48:45Z                                 |
| disk_format      | qcow2                                                |
| file             | /v2/images/06416c27-d6e2-4aa8-ad7a-1d3450f8af6f/file |
| id               | 06416c27-d6e2-4aa8-ad7a-1d3450f8af6f                 |
| min_disk         | 0                                                    |
| min_ram          | 0                                                    |
| name             | cirros                                               |
| owner            | 3d50dde76a424b7bbf5fc6e97a67a7a4                     |
| protected        | False                                                |
| status           | queued                                               |
| tags             |                                                      |
| updated_at       | 2025-01-27T01:48:45Z                                 |
| visibility       | public                                               |
+------------------+------------------------------------------------------+
```

The `status` changes from `queued` to `active` once the upload completes.

### Verify the Image

List all images:

```bash
openstack image list
```

Output:

```
+--------------------------------------+--------+--------+
| ID                                   | Name   | Status |
+--------------------------------------+--------+--------+
| 06416c27-d6e2-4aa8-ad7a-1d3450f8af6f | cirros | active |
+--------------------------------------+--------+--------+
```

Get detailed image information:

```bash
openstack image show cirros
```

This displays all image properties including checksum, size, and visibility.

### Upload Ubuntu 22.04 Image

For a more realistic VM, upload an Ubuntu cloud image:

```bash
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

Upload to Glance:

```bash
openstack image create "Ubuntu 22.04" \
  --file jammy-server-cloudimg-amd64.img \
  --disk-format qcow2 \
  --container-format bare \
  --public
```

Output:

```
+------------------+------------------------------------------------------+
| Field            | Value                                                |
+------------------+------------------------------------------------------+
| container_format | bare                                                 |
| created_at       | 2025-02-02T21:23:26Z                                 |
| disk_format      | qcow2                                                |
| file             | /v2/images/4d160383-4273-407d-b6fd-09224d7ea35d/file |
| id               | 4d160383-4273-407d-b6fd-09224d7ea35d                 |
| min_disk         | 0                                                    |
| min_ram          | 0                                                    |
| name             | Ubuntu 22.04                                         |
| owner            | be58db082a2644369e44d643b86d1286                     |
| protected        | False                                                |
| status           | queued                                               |
| tags             |                                                      |
| updated_at       | 2025-02-02T21:23:26Z                                 |
| visibility       | public                                               |
+------------------+------------------------------------------------------+
```

List images again:

```bash
openstack image list
```

Output:

```
+--------------------------------------+--------------+--------+
| ID                                   | Name         | Status |
+--------------------------------------+--------------+--------+
| 06416c27-d6e2-4aa8-ad7a-1d3450f8af6f | cirros       | active |
| 4d160383-4273-407d-b6fd-09224d7ea35d | Ubuntu 22.04 | active |
+--------------------------------------+--------------+--------+
```

Both images are now available for launching instances.

## Image Storage Backend

By default, Glance stores images on the local filesystem in `/var/lib/glance/images/`. For production deployments, consider:

- **Swift**: OpenStack object storage (covered later in this series)
- **Ceph**: Distributed storage with replication
- **NFS**: Network filesystem for shared storage
- **S3-compatible**: MinIO, AWS S3, etc.

This deployment uses the filesystem backend for simplicity.

## Common Issues and Troubleshooting

### Glance API Not Starting

Check the service status and logs:

```bash
sudo systemctl status glance-api
sudo journalctl -u glance-api -n 50
```

Common issues:
- Database connection failures (wrong credentials or hostname)
- Port 9292 already in use
- Missing configuration sections

### Image Upload Failures

If `openstack image create` fails:

1. **Check disk space**:
   ```bash
   df -h /var/lib/glance/
   ```

2. **Verify Glance API is reachable**:
   ```bash
   curl http://controller:9292
   ```

3. **Check Glance logs**:
   ```bash
   sudo tail -f /var/log/glance/glance-api.log
   ```

4. **Test Keystone authentication**:
   ```bash
   openstack token issue
   ```

### Images Stuck in "Queued" Status

If images remain in `queued` status:

- Glance may not have write permissions to the image directory:
  ```bash
  sudo chown -R glance:glance /var/lib/glance/
  ```

- Check for disk space issues
- Restart Glance API:
  ```bash
  sudo systemctl restart glance-api
  ```

### Authentication Errors

If Glance can't authenticate with Keystone:

- Verify the `[keystone_authtoken]` section in `/etc/glance/glance-api.conf`
- Check the Glance user exists: `openstack user show glance`
- Verify the password matches
- Ensure memcached is running on Keystone node

## What's Next

With Glance operational and images uploaded, Nova can launch instances. The next post covers Nova installation on a dedicated compute node, including hypervisor configuration and instance lifecycle management.

## Summary

This post covered:

- Cloning the Glance VM from the base template
- Configuring networking and hostname
- Creating the Glance database in MariaDB
- Creating the Glance service user in Keystone
- Registering Glance in the service catalog with endpoints
- Installing and configuring Glance
- Initializing the Glance database schema
- Uploading CirrOS and Ubuntu images
- Listing and inspecting images
- Troubleshooting common Glance issues

Glance is now managing VM images for the OpenStack environment. In the next post, we'll install Nova to launch instances using these images.
