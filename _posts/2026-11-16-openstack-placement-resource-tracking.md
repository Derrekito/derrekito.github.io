---
title: "OpenStack Placement: Resource Tracking and Inventory Management"
date: 2026-11-16
categories: [Cloud Computing, Infrastructure]
tags: [openstack, placement, resource-tracking, scheduling, inventory]
---

Placement is OpenStack's resource tracking service, managing inventories of available resources (CPU, RAM, disk) across compute nodes. Nova's scheduler uses Placement to find compute hosts with sufficient resources to run instances. By tracking allocations and consumption, Placement ensures the scheduler doesn't over-commit resources or schedule instances on hosts that can't accommodate them.

This post covers Placement installation on the Keystone node, configuration, and verification of resource tracking functionality.

## What Placement Does

Before Placement existed, Nova's scheduler tracked resources internally, leading to scalability and consistency issues. Placement extracted this functionality into a dedicated service with a clear API.

Placement provides:

1. **Resource Inventory**: Tracks what resources exist on each compute node
2. **Resource Allocation**: Records which instances consume which resources
3. **Resource Classes**: Defines types of resources (VCPU, MEMORY_MB, DISK_GB, custom resources)
4. **Traits**: Describes capabilities of resource providers (e.g., supports AVX2, has GPU)
5. **Allocation Candidates**: Finds resource providers that match scheduling requirements

When Nova needs to launch an instance:

1. Nova asks Placement: "Which compute hosts have 2 vCPUs, 4096 MB RAM, and 20 GB disk available?"
2. Placement returns a list of candidate hosts
3. Nova's scheduler applies filters and weighing to select the best candidate
4. Nova tells Placement: "Allocate these resources on the selected host"
5. Placement records the allocation to prevent double-booking

### Resource Providers

A **resource provider** is any entity that provides consumable resources. Typically this is a compute node, but it can also be:

- Shared storage pools
- Network bandwidth providers
- GPU nodes
- NUMA nodes within a compute host

Each provider reports its inventory to Placement and receives allocations when resources are consumed.

### Resource Classes

Placement defines standard resource classes:

- **VCPU**: Virtual CPU cores
- **MEMORY_MB**: RAM in megabytes
- **DISK_GB**: Disk storage in gigabytes
- **PCI_DEVICE**: PCI passthrough devices
- **SRIOV_NET_VF**: SR-IOV virtual functions

Custom resource classes can be created for specialized resources (e.g., `CUSTOM_FPGA`).

### Traits

Traits describe qualitative capabilities rather than quantitative resources:

- `HW_CPU_X86_AVX2`: CPU supports AVX2 instructions
- `HW_GPU_API_OPENGL`: GPU supports OpenGL
- `STORAGE_DISK_SSD`: Storage is SSD rather than HDD
- `CUSTOM_WINDOWS_LICENSE`: Host has Windows licensing

Traits enable capability-based scheduling (e.g., "find a host with AVX2 support").

## Prerequisites

Before installing Placement:

- Keystone operational
- MariaDB accessible from Keystone node
- Nova installed (Placement runs on the Keystone node but integrates with Nova)

## Installing Placement on the Keystone Node

Placement runs on the Keystone node to keep the deployment compact. In production, it can run on any controller node.

SSH to the Keystone VM:

```bash
ssh openstack@keystone
```

## Creating the Placement Database

Create the Placement database on the Keystone node:

```bash
sudo mysql -u root -p
```

In the MariaDB prompt:

```sql
CREATE DATABASE placement;

GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY 'PLACEMENT_DBPASS';
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY 'PLACEMENT_DBPASS';

EXIT;
```

Replace `PLACEMENT_DBPASS` with a secure password.

Verify the database:

```bash
mysql -u placement -p -e "SHOW DATABASES;"
```

You should see `placement` in the list.

## Creating the Placement User in Keystone

Create the Placement service user:

```bash
openstack user create --domain default --password-prompt placement
```

Enter the password when prompted.

Output:

```
+---------------------+----------------------------------+
| Field               | Value                            |
+---------------------+----------------------------------+
| domain_id           | default                          |
| enabled             | True                             |
| id                  | 08b1f69a17fc42b58a6e823f2785c587 |
| name                | placement                        |
| options             | {}                               |
| password_expires_at | None                             |
+---------------------+----------------------------------+
```

Add the `admin` role to the `placement` user in the `service` project:

```bash
openstack role add --project service --user placement admin
```

This command produces no output on success.

## Registering Placement in the Service Catalog

Create the Placement service:

```bash
openstack service create --name placement --description "Placement API" placement
```

Output:

```
+-------------+----------------------------------+
| Field       | Value                            |
+-------------+----------------------------------+
| description | Placement API                    |
| enabled     | True                             |
| id          | 7cb4211f1614460386877bb005562b87 |
| name        | placement                        |
| type        | placement                        |
+-------------+----------------------------------+
```

Create the three endpoints (public, internal, admin):

```bash
openstack endpoint create --region RegionOne placement public http://keystone:8778
openstack endpoint create --region RegionOne placement internal http://keystone:8778
openstack endpoint create --region RegionOne placement admin http://controller:8778
```

Each endpoint command outputs:

```
+--------------+----------------------------------+
| Field        | Value                            |
+--------------+----------------------------------+
| enabled      | True                             |
| id           | 6c19d4354f0b4ef8b601dc3b0d846c38 |
| interface    | public                           |
| region       | RegionOne                        |
| service_id   | 7cb4211f1614460386877bb005562b87 |
| service_name | placement                        |
| service_type | placement                        |
| url          | http://keystone:8778             |
+--------------+----------------------------------+
```

Note that Placement runs on port 8778.

## Installing the Placement Service

Install the Placement API package:

```bash
sudo apt install -y placement-api
```

Placement runs as a WSGI application under Apache2 (similar to Keystone).

## Configuring Placement

Edit the Placement configuration file at `/etc/placement/placement.conf`:

```bash
sudo nano /etc/placement/placement.conf
```

### Default Section

```ini
[DEFAULT]
debug = false
use_stderr = false
```

Set `debug = true` if troubleshooting is needed.

### Database Connection

```ini
[placement_database]
connection = mysql+pymysql://placement:PLACEMENT_DBPASS@keystone/placement
```

Replace `PLACEMENT_DBPASS` with the database password.

### API Authentication

```ini
[api]
auth_strategy = keystone
```

This tells Placement to use Keystone for authentication.

### Keystone Authentication Token

```ini
[keystone_authtoken]
auth_url = http://keystone:5000/v3
memcached_servers = keystone:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = placement
password = PLACEMENT_DBPASS
```

Replace `PLACEMENT_DBPASS` with the Placement user password.

Save and exit the configuration file.

## Initializing the Placement Database

Populate the Placement database schema:

```bash
sudo -u placement placement-manage db sync
```

This creates the tables for resource providers, inventories, allocations, and traits.

## Restarting Services

Restart Apache2 to load the Placement WSGI application:

```bash
sudo systemctl restart apache2
```

Verify Apache2 is running:

```bash
sudo systemctl status apache2
```

## Restarting Nova Services

Nova needs to be restarted to recognize Placement. On the Nova node:

```bash
ssh openstack@nova
sudo systemctl restart nova-api nova-scheduler nova-conductor nova-compute
```

Or use a wildcard (requires authentication for each service):

```bash
sudo systemctl restart nova-*
```

## Verifying Placement Operation

Check Placement status with the built-in upgrade check:

```bash
sudo placement-status upgrade check
```

Expected output:

```
+-------------------------------------------+
| Upgrade Check Results                     |
+-------------------------------------------+
| Check: Missing Root Provider IDs          |
| Result: Success                           |
| Details: None                             |
+-------------------------------------------+
| Check: Incomplete Consumers               |
| Result: Success                           |
| Details: None                             |
+-------------------------------------------+
| Check: Policy File JSON to YAML Migration |
| Result: Success                           |
| Details: None                             |
+-------------------------------------------+
```

All checks should show `Result: Success`.

## Viewing Resource Providers

After Nova compute services report to Placement, resource providers appear:

```bash
openstack resource provider list
```

Output (after Nova reports):

```
+--------------------------------------+------+------------+
| uuid                                 | name | generation |
+--------------------------------------+------+------------+
| 5aee789f-4bc0-4935-9655-a2f78238c31e | nova |          2 |
+--------------------------------------+------+------------+
```

The `nova` compute node is registered as a resource provider.

### Viewing Resource Inventory

Check what resources the compute node provides:

```bash
openstack resource provider inventory list <provider-uuid>
```

Example output:

```
+----------------+------------------+----------+----------+-----------+----------+--------+
| resource_class | allocation_ratio | max_unit | reserved | step_size | min_unit |  total |
+----------------+------------------+----------+----------+-----------+----------+--------+
| VCPU           |             16.0 |        2 |        0 |         1 |        1 |      2 |
| MEMORY_MB      |              1.5 |     2048 |      512 |         1 |        1 |   2048 |
| DISK_GB        |              1.0 |       25 |        0 |         1 |        1 |     25 |
+----------------+------------------+----------+----------+-----------+----------+--------+
```

This shows the Nova compute node has:
- 2 vCPUs (with 16x overcommit ratio)
- 2048 MB RAM (with 1.5x overcommit ratio)
- 25 GB disk (no overcommit)

The `allocation_ratio` allows oversubscription. An allocation ratio of 16.0 for VCPU means Nova can allocate up to 32 vCPUs (2 * 16) assuming not all instances use full CPU simultaneously.

### Viewing Allocations

Check which resources are allocated to instances:

```bash
openstack resource provider allocation show <provider-uuid>
```

Before any instances are launched, allocations are empty. After launching an instance, allocations appear:

```
+----------------+--------+
| resource_class | used   |
+----------------+--------+
| VCPU           |      1 |
| MEMORY_MB      |   2048 |
| DISK_GB        |     20 |
+----------------+--------+
```

This shows one instance consuming 1 vCPU, 2048 MB RAM, and 20 GB disk.

## Testing Placement Integration with Nova

Verify Nova can query Placement:

```bash
openstack --os-placement-api-version 1.36 resource provider list
```

If this command returns resource providers, Nova and Placement are communicating correctly.

## Common Issues and Troubleshooting

### Placement API Not Responding

If Placement endpoints are unreachable:

1. **Check Apache2 is running**:
   ```bash
   sudo systemctl status apache2
   ```

2. **Verify Placement is listening on port 8778**:
   ```bash
   sudo ss -tulnp | grep 8778
   ```

3. **Check Apache error logs**:
   ```bash
   sudo tail -f /var/log/apache2/error.log
   ```

4. **Verify Placement WSGI configuration**:
   ```bash
   ls /etc/apache2/sites-enabled/ | grep placement
   ```

### No Resource Providers Listed

If `openstack resource provider list` returns empty:

- Nova compute services may not have started or connected to Placement
- Check Nova compute logs:
  ```bash
  sudo journalctl -u nova-compute -n 50
  ```
- Verify the `[placement]` section in `/etc/nova/nova.conf` on the Nova node
- Restart Nova compute:
  ```bash
  sudo systemctl restart nova-compute
  ```

### Database Connection Failures

If Placement can't connect to the database:

- Verify credentials in `/etc/placement/placement.conf`
- Test database connection:
  ```bash
  mysql -h keystone -u placement -p placement
  ```
- Check MariaDB is accessible from the Keystone node

### Authentication Errors

If Placement returns 401 Unauthorized errors:

- Verify the `[keystone_authtoken]` section in `/etc/placement/placement.conf`
- Check the Placement user exists:
  ```bash
  openstack user show placement
  ```
- Verify the password matches
- Restart Apache2:
  ```bash
  sudo systemctl restart apache2
  ```

### Upgrade Check Failures

If `placement-status upgrade check` shows failures:

- **Missing Root Provider IDs**: Run database migration again:
  ```bash
  sudo -u placement placement-manage db sync
  ```
- **Incomplete Consumers**: Clean up orphaned allocations:
  ```bash
  sudo -u placement placement-manage db online_data_migrations
  ```

## Understanding Resource Allocation Flow

When Nova launches an instance:

1. **Request**: User requests instance with flavor (e.g., 1 vCPU, 2048 MB RAM, 20 GB disk)
2. **Placement Query**: Nova scheduler asks Placement for hosts with sufficient resources
3. **Candidate Selection**: Placement returns resource providers that meet requirements
4. **Scheduling**: Nova scheduler applies filters (availability zone, host aggregates) and weighs candidates
5. **Allocation**: Nova tells Placement to allocate resources on the selected host
6. **Instance Creation**: Nova compute creates the instance using the allocated resources

This flow ensures:
- Resources aren't double-allocated
- Scheduling decisions are based on accurate inventory
- Resource consumption is tracked centrally

## What's Next

With Placement operational, Nova can accurately track resource usage and make informed scheduling decisions. The next post covers Neutron, the networking service that provides virtual networks, routers, and floating IPs for instances.

## Summary

This post covered:

- The role of Placement in resource tracking and scheduling
- Resource providers, classes, and traits concepts
- Installing Placement on the Keystone node
- Creating the Placement database
- Creating the Placement service user in Keystone
- Registering Placement in the service catalog
- Configuring Placement for database and Keystone integration
- Initializing the Placement database
- Verifying Placement operation with upgrade checks
- Viewing resource providers, inventory, and allocations
- Troubleshooting Placement connectivity and authentication issues

Placement is now tracking compute resources and enabling Nova's scheduler to make intelligent placement decisions. In the next post, we'll install Neutron to provide virtual networking for instances.
