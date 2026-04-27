---
title: "OpenStack Swift: Object Storage for Unstructured Data"
date: 2026-12-14
categories: [Cloud Computing, Infrastructure]
tags: [openstack, swift, object-storage, distributed-storage, rest-api, s3-compatible]
---

Swift provides object storage services for OpenStack, designed to store and retrieve unstructured data at scale. Unlike block storage (Cinder) which provides volumes for instances, Swift stores files, backups, images, archives, and other blob data through a RESTful HTTP API. Swift is designed for high availability and fault tolerance, distributing data across multiple nodes with automatic replication.

This post covers Swift installation with a proxy node on Keystone and storage nodes on a dedicated VM, ring configuration for data distribution, and demonstrates creating containers and uploading objects.

## What Swift Does

Swift provides distributed object storage:

1. **Object Storage**: Store files as objects (blobs of data with metadata)
2. **Container Management**: Organize objects into containers (similar to S3 buckets)
3. **Account Management**: Namespace for containers and objects per project
4. **Replication**: Automatically replicate objects across multiple nodes
5. **Distribution**: Distribute data across storage zones for fault tolerance
6. **REST API**: HTTP-based API compatible with S3 (with middleware)
7. **Large Object Support**: Handle files larger than 5 GB through segmentation

Swift is ideal for:
- VM image storage (Glance backend)
- Volume backups (Cinder backup target)
- Static website hosting
- Media files and archives
- Log aggregation
- Big data storage

### Swift Architecture

Swift consists of several components:

**Proxy Nodes** (frontend):
- **swift-proxy**: Receives API requests, routes to storage nodes
- **Authentication**: Integrates with Keystone for access control
- **Load balancing**: Distributes requests across storage nodes

**Storage Nodes** (backend):
- **swift-account**: Manages account metadata and container lists
- **swift-container**: Manages container metadata and object lists
- **swift-object**: Manages actual object data

**Consistency Services**:
- **Replicators**: Ensure data is replicated to all designated nodes
- **Updaters**: Propagate metadata updates
- **Auditors**: Verify data integrity

### The Ring

Swift uses a modified consistent hashing ring to determine object placement:

- **Ring**: Maps data to physical locations
- **Partitions**: Logical divisions of the ring (typically 2^n partitions)
- **Replicas**: Number of copies of each object (typically 3)
- **Zones**: Failure domains (racks, datacenters)

The ring ensures even data distribution and allows adding/removing storage without rebalancing all data.

### Object Storage vs. Block Storage

| Feature | Swift (Object) | Cinder (Block) |
|---------|----------------|----------------|
| Access | HTTP REST API | iSCSI/block device |
| Use case | Files, backups, archives | Instance volumes, databases |
| Mountable | No | Yes (as /dev/vdb) |
| File system | N/A (objects) | Created by user (ext4, xfs) |
| Scalability | Petabytes+ | Limited by backend |
| Performance | Throughput-optimized | IOPS-optimized |

## Prerequisites

Before installing Swift:

- Keystone operational (Swift proxy runs on Keystone node)
- Memcached running on Keystone node
- Base VM template available
- Additional disks for object storage

## Installing Swift Proxy on Keystone Node

Swift's proxy service runs on the Keystone node. SSH to Keystone:

```bash
ssh openstack@keystone
```

### Creating the Swift User in Keystone

Create the Swift service user:

```bash
openstack user create --domain default --password-prompt swift
```

Add the admin role:

```bash
openstack role add --project service --user swift admin
```

### Registering Swift Service

Create the object storage service:

```bash
openstack service create --name swift --description "OpenStack Object Storage" object-store
```

Create endpoints:

```bash
openstack endpoint create --region RegionOne object-store public http://keystone:8080/v1/AUTH_%\(project_id\)s
openstack endpoint create --region RegionOne object-store internal http://keystone:8080/v1/AUTH_%\(project_id\)s
openstack endpoint create --region RegionOne object-store admin http://keystone:8080/v1
```

Swift listens on port 8080. The `AUTH_%(project_id)s` is substituted with the project ID.

### Installing Swift Proxy Packages

Install the proxy and client packages:

```bash
sudo apt-get install -y swift swift-proxy python3-swiftclient python3-keystoneclient python3-keystonemiddleware memcached
```

### Creating Swift Configuration Directory

```bash
sudo mkdir -p /etc/swift
```

### Downloading Proxy Configuration Template

Download the sample configuration:

```bash
sudo curl -o /etc/swift/proxy-server.conf https://opendev.org/openstack/swift/raw/branch/master/etc/proxy-server.conf-sample
```

### Configuring Swift Proxy

Edit `/etc/swift/proxy-server.conf`:

```bash
sudo nano /etc/swift/proxy-server.conf
```

**[DEFAULT] Section**:

```ini
[DEFAULT]
bind_port = 8080
user = swift
swift_dir = /etc/swift
```

**[pipeline:main] Section**:

```ini
[pipeline:main]
pipeline = catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk ratelimit authtoken keystoneauth container-quotas account-quotas slo dlo versioned_writes proxy-logging proxy-server
```

This pipeline defines the middleware processing order.

**[app:proxy-server] Section**:

```ini
[app:proxy-server]
use = egg:swift#proxy
account_autocreate = True
```

`account_autocreate` allows Swift to automatically create accounts on first use.

**[filter:keystoneauth] Section**:

```ini
[filter:keystoneauth]
use = egg:swift#keystoneauth
operator_roles = admin,user
```

**[filter:authtoken] Section**:

```ini
[filter:authtoken]
paste.filter_factory = keystonemiddleware.auth_token:filter_factory
www_authenticate_uri = http://keystone:5000
auth_url = http://keystone:5000
memcached_servers = keystone:11211
auth_type = password
project_domain_id = default
user_domain_id = default
project_name = service
username = swift
password = SWIFT_PASS
delay_auth_decision = True
```

**[filter:cache] Section**:

```ini
[filter:cache]
use = egg:swift#memcache
memcache_servers = keystone:11211
```

## Cloning the Swift Storage Node VM

Clone the base VM:

1. Right-click **BaseVM**
2. Select **Clone**
3. Name: `Swift`
4. MAC Address Policy: **Generate new MAC addresses**
5. Clone type: **Full clone**

**Add Storage Disks**: Before starting, add two additional virtual disks:

1. Select Swift VM → **Settings → Storage**
2. Add two disks (e.g., 10 GB each)
3. Click **OK**

Start the Swift VM and log in.

## Configuring the Swift Storage Node

Update network configuration:

```bash
# Update Netplan to set static IP to 192.168.56.109
sudo sed -i 's/192\.168\.56\.10[0-9]\/24/192.168.56.109\/24/' /etc/netplan/*

# Update hostname
sudo hostnamectl set-hostname swift

# Apply configuration
sudo netplan apply
```

### Preparing Storage Disks

Install XFS utilities and rsync:

```bash
sudo apt-get install -y xfsprogs rsync
```

Format the additional disks with XFS:

```bash
sudo mkfs.xfs /dev/sdb
sudo mkfs.xfs /dev/sdc
```

Create mount points:

```bash
sudo mkdir -p /srv/node/sdb
sudo mkdir -p /srv/node/sdc
```

Get disk UUIDs:

```bash
sudo blkid
```

Output:

```
/dev/sdb: UUID="a1b2c3d4-..." TYPE="xfs"
/dev/sdc: UUID="e5f6g7h8-..." TYPE="xfs"
```

Edit `/etc/fstab` to mount disks on boot:

```bash
sudo nano /etc/fstab
```

Add entries:

```
UUID="a1b2c3d4-..." /srv/node/sdb xfs noatime 0 2
UUID="e5f6g7h8-..." /srv/node/sdc xfs noatime 0 2
```

Mount the disks:

```bash
sudo mount /srv/node/sdb
sudo mount /srv/node/sdc
```

Verify mounts:

```bash
df -h | grep srv
```

### Configuring rsync for Replication

Edit `/etc/rsyncd.conf`:

```bash
sudo nano /etc/rsyncd.conf
```

Add configuration:

```ini
uid = swift
gid = swift
log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid
address = 192.168.56.109

[account]
max connections = 2
path = /srv/node/
read only = False
lock file = /var/lock/account.lock

[container]
max connections = 2
path = /srv/node/
read only = False
lock file = /var/lock/container.lock

[object]
max connections = 2
path = /srv/node/
read only = False
lock file = /var/lock/object.lock
```

Enable rsync:

```bash
sudo nano /etc/default/rsync
```

Set:

```
RSYNC_ENABLE=true
```

Start rsync:

```bash
sudo systemctl enable rsync
sudo systemctl start rsync
```

### Installing Swift Storage Packages

```bash
sudo apt-get install -y swift swift-account swift-container swift-object
```

### Downloading Storage Server Configuration Templates

```bash
sudo curl -o /etc/swift/account-server.conf https://opendev.org/openstack/swift/raw/branch/master/etc/account-server.conf-sample
sudo curl -o /etc/swift/container-server.conf https://opendev.org/openstack/swift/raw/branch/master/etc/container-server.conf-sample
sudo curl -o /etc/swift/object-server.conf https://opendev.org/openstack/swift/raw/branch/master/etc/object-server.conf-sample
```

### Configuring Account Server

Edit `/etc/swift/account-server.conf`:

```ini
[DEFAULT]
bind_ip = 192.168.56.109
bind_port = 6202
user = swift
swift_dir = /etc/swift
devices = /srv/node
mount_check = True

[pipeline:main]
pipeline = healthcheck recon account-server

[filter:recon]
use = egg:swift#recon
recon_cache_path = /var/cache/swift
```

### Configuring Container Server

Edit `/etc/swift/container-server.conf`:

```ini
[DEFAULT]
bind_ip = 192.168.56.109
bind_port = 6201
user = swift
swift_dir = /etc/swift
devices = /srv/node
mount_check = True

[pipeline:main]
pipeline = healthcheck recon container-server

[filter:recon]
use = egg:swift#recon
recon_cache_path = /var/cache/swift
```

### Configuring Object Server

Edit `/etc/swift/object-server.conf`:

```ini
[DEFAULT]
bind_ip = 192.168.56.109
bind_port = 6200
user = swift
swift_dir = /etc/swift
devices = /srv/node
mount_check = True

[pipeline:main]
pipeline = healthcheck recon object-server

[filter:recon]
use = egg:swift#recon
recon_cache_path = /var/cache/swift
recon_lock_path = /var/lock
```

### Setting Permissions

Set ownership of storage directories:

```bash
sudo chown -R swift:swift /srv/node
```

Create and configure cache directory:

```bash
sudo mkdir -p /var/cache/swift
sudo chown -R root:swift /var/cache/swift
sudo chmod -R 775 /var/cache/swift
```

## Creating Swift Rings

Rings must be created on the proxy node (Keystone). SSH to Keystone:

```bash
ssh openstack@keystone
cd /etc/swift
```

### Create Account Ring

```bash
sudo swift-ring-builder account.builder create 10 3 1
```

Parameters:
- `10`: 2^10 = 1024 partitions
- `3`: 3 replicas
- `1`: 1 hour minimum time between moving a partition

Add storage devices:

```bash
sudo swift-ring-builder account.builder add --region 1 --zone 1 --ip 192.168.56.109 --port 6202 --device sdb --weight 100
sudo swift-ring-builder account.builder add --region 1 --zone 1 --ip 192.168.56.109 --port 6202 --device sdc --weight 100
```

Rebalance the ring:

```bash
sudo swift-ring-builder account.builder rebalance
```

### Create Container Ring

```bash
sudo swift-ring-builder container.builder create 10 3 1
sudo swift-ring-builder container.builder add --region 1 --zone 1 --ip 192.168.56.109 --port 6201 --device sdb --weight 100
sudo swift-ring-builder container.builder add --region 1 --zone 1 --ip 192.168.56.109 --port 6201 --device sdc --weight 100
sudo swift-ring-builder container.builder rebalance
```

### Create Object Ring

```bash
sudo swift-ring-builder object.builder create 10 3 1
sudo swift-ring-builder object.builder add --region 1 --zone 1 --ip 192.168.56.109 --port 6200 --device sdb --weight 100
sudo swift-ring-builder object.builder add --region 1 --zone 1 --ip 192.168.56.109 --port 6200 --device sdc --weight 100
sudo swift-ring-builder object.builder rebalance
```

### Verify Rings

```bash
sudo swift-ring-builder account.builder
sudo swift-ring-builder container.builder
sudo swift-ring-builder object.builder
```

### Copy Rings to Storage Node

Copy ring files to the Swift storage node:

```bash
scp /etc/swift/*.ring.gz openstack@swift:/tmp/
ssh openstack@swift 'sudo mv /tmp/*.ring.gz /etc/swift/ && sudo chown swift:swift /etc/swift/*.ring.gz'
```

## Creating Swift Configuration File

On the Keystone node, create `/etc/swift/swift.conf`:

```bash
sudo nano /etc/swift/swift.conf
```

Add:

```ini
[swift-hash]
swift_hash_path_suffix = HASH_PATH_SUFFIX
swift_hash_path_prefix = HASH_PATH_PREFIX

[storage-policy:0]
name = Policy-0
default = yes
```

Replace `HASH_PATH_SUFFIX` and `HASH_PATH_PREFIX` with random strings:

```bash
openssl rand -hex 10
```

Copy to storage node:

```bash
scp /etc/swift/swift.conf openstack@swift:/tmp/
ssh openstack@swift 'sudo mv /tmp/swift.conf /etc/swift/ && sudo chown swift:swift /etc/swift/swift.conf'
```

## Starting Swift Services

On the Keystone node (proxy):

```bash
sudo systemctl enable swift-proxy
sudo systemctl start swift-proxy
```

On the Swift storage node:

```bash
sudo systemctl enable swift-account swift-account-auditor swift-account-reaper swift-account-replicator
sudo systemctl enable swift-container swift-container-auditor swift-container-replicator swift-container-updater
sudo systemctl enable swift-object swift-object-auditor swift-object-replicator swift-object-updater
sudo systemctl start swift-account swift-account-auditor swift-account-reaper swift-account-replicator
sudo systemctl start swift-container swift-container-auditor swift-container-replicator swift-container-updater
sudo systemctl start swift-object swift-object-auditor swift-object-replicator swift-object-updater
```

## Using Swift: Creating Containers and Objects

### Create a Container

```bash
openstack container create test-container
```

Output:

```
+---------------------------------------+----------------+------------------------------------+
| account                               | container      | x-trans-id                         |
+---------------------------------------+----------------+------------------------------------+
| AUTH_3d50dde76a424b7bbf5fc6e97a67a7a4 | test-container | tx000001-abcdef-keystone-RegionOne |
+---------------------------------------+----------------+------------------------------------+
```

### List Containers

```bash
openstack container list
```

Output:

```
+----------------+
| Name           |
+----------------+
| test-container |
+----------------+
```

### Upload an Object

```bash
echo "Hello Swift" > test-file.txt
openstack object create test-container test-file.txt
```

Output:

```
+--------------+----------------+----------------------------------+
| object       | container      | etag                             |
+--------------+----------------+----------------------------------+
| test-file.txt| test-container | 9a0364b9e99bb480dd25e1f0284c8555 |
+--------------+----------------+----------------------------------+
```

### List Objects in Container

```bash
openstack object list test-container
```

Output:

```
+---------------+
| Name          |
+---------------+
| test-file.txt |
+---------------+
```

### Download an Object

```bash
openstack object save test-container test-file.txt
```

### Delete an Object

```bash
openstack object delete test-container test-file.txt
```

### Delete a Container

```bash
openstack container delete test-container
```

## Accessing Swift via Horizon

1. Navigate to **Project → Object Store → Containers**
2. Click **Create Container**
3. Enter container name → **Create**
4. Click the container name
5. Click **Upload File** to upload objects
6. View, download, or delete objects

## Common Issues and Troubleshooting

### Swift Proxy Not Responding

If Swift endpoints return errors:

1. **Check proxy service**:
   ```bash
   sudo systemctl status swift-proxy
   ```

2. **Check logs**:
   ```bash
   sudo tail -f /var/log/syslog | grep swift
   ```

3. **Verify Keystone authentication**:
   ```bash
   openstack token issue
   ```

### Ring Files Missing

If storage nodes can't find rings:

- Verify ring files exist:
  ```bash
  ls -la /etc/swift/*.ring.gz
  ```

- Verify ownership:
  ```bash
  sudo chown swift:swift /etc/swift/*.ring.gz
  ```

### Disks Not Mounting

If storage disks fail to mount:

- Check `/etc/fstab` entries
- Verify UUIDs match: `sudo blkid`
- Check mount errors: `sudo dmesg | grep sdb`

### Replication Failures

If replication doesn't work:

- Verify rsync is running: `sudo systemctl status rsync`
- Check rsync connectivity: `rsync swift::account`
- Review replicator logs

## What's Next

With Swift operational, OpenStack has both block storage (Cinder) and object storage (Swift). The remaining posts cover containerization with Docker and automation with Ansible, applying these cloud concepts to practical deployments.

## Summary

This post covered:

- Swift's role in providing distributed object storage
- Architecture with proxy nodes and storage nodes
- Ring-based data distribution and replication
- Installing Swift proxy on Keystone node
- Creating Swift service user and endpoints
- Configuring Swift proxy with Keystone authentication
- Cloning Swift storage node VM
- Preparing XFS-formatted storage disks
- Configuring rsync for data replication
- Installing and configuring account, container, and object servers
- Creating rings for account, container, and object data
- Distributing ring files to storage nodes
- Starting Swift services
- Creating containers and uploading objects
- Accessing Swift via CLI and Horizon
- Troubleshooting proxy, rings, disk mounts, and replication

Swift is now providing scalable object storage for OpenStack. The OpenStack core services (identity, compute, networking, dashboard, block storage, object storage) are complete. The next posts transition to containerization with Docker and automation with Ansible.
