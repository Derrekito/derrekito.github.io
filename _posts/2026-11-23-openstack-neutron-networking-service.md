---
title: "OpenStack Neutron: Networking Service for Virtual Networks"
date: 2026-11-23
categories: [Cloud Computing, Infrastructure]
tags: [openstack, neutron, networking, sdn, vxlan, linuxbridge, dhcp]
---

Neutron provides Network-as-a-Service (NaaS) functionality for OpenStack, managing virtual networks, subnets, routers, and IP addresses. It enables instances to communicate with each other and the external network through software-defined networking (SDN). Neutron supports advanced features including load balancing, firewalls, VPNs, and floating IPs, making it essential for production cloud deployments.

This post covers Neutron installation on a dedicated networking node, configuration with the ML2 plugin and Linux Bridge agent, and demonstrates creating networks and subnets.

## What Neutron Does

Neutron orchestrates all networking for OpenStack:

1. **Network Management**: Creates isolated virtual networks (VLANs, VXLAN overlays, flat networks)
2. **Subnet Management**: Defines IP address ranges and DHCP configuration
3. **Router Management**: Routes traffic between networks and to external networks
4. **Floating IPs**: Provides public IP addresses for instances
5. **Security Groups**: Implements firewall rules per instance
6. **Load Balancing**: Distributes traffic across multiple instances (LBaaS)
7. **VPN**: Connects cloud networks to external networks (VPNaaS)

### Neutron Architecture

Neutron consists of several components:

- **neutron-server**: API server that receives network requests
- **ML2 Plugin**: Modular Layer 2 plugin supporting multiple network types (flat, VLAN, VXLAN, GRE)
- **L2 Agent**: Implements network connectivity on compute/network nodes (Linux Bridge, Open vSwitch)
- **L3 Agent**: Implements routing and NAT (not covered in this deployment)
- **DHCP Agent**: Provides DHCP services to instances
- **Metadata Agent**: Provides cloud-init metadata to instances

### Network Types

- **Flat**: Untagged network, typically used for provider networks
- **VLAN**: Tagged 802.1Q networks for tenant isolation
- **VXLAN**: Overlay network tunneling, scales beyond VLAN's 4096 limit
- **GRE**: Generic Routing Encapsulation tunneling

This deployment uses:
- **Flat** for provider networks (external access)
- **VXLAN** for tenant networks (instance-to-instance communication)

### Linux Bridge vs. Open vSwitch

Neutron supports two L2 agents:

- **Linux Bridge**: Simple, kernel-native bridging
- **Open vSwitch**: Feature-rich virtual switch with advanced capabilities

This deployment uses Linux Bridge for simplicity. Production deployments often prefer Open vSwitch for features like GRE tunneling and flow-based forwarding.

## Prerequisites

Before installing Neutron:

- Keystone, RabbitMQ, Nova, and Placement operational
- Base VM template available

## Cloning the Neutron VM

Clone the base VM in VirtualBox:

1. Right-click **BaseVM**
2. Select **Clone**
3. Name: `Neutron`
4. MAC Address Policy: **Generate new MAC addresses for all network adapters**
5. Clone type: **Full clone**
6. Click **Clone**

Start the Neutron VM and log in.

## Configuring the Neutron VM

Update network configuration:

```bash
# Update Netplan to set static IP to 192.168.56.106
sudo sed -i 's/192\.168\.56\.10[0-9]\/24/192.168.56.106\/24/' /etc/netplan/*

# Update hostname
sudo hostnamectl set-hostname neutron

# Apply the configuration
sudo netplan apply
```

Test SSH from the host:

```bash
ssh openstack@neutron
```

## Creating the Neutron Database

Connect to MariaDB on the Keystone node:

```bash
mysql -h keystone -u root -p
```

In the MariaDB prompt:

```sql
CREATE DATABASE neutron;

GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY 'NEUTRON_DBPASS';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY 'NEUTRON_DBPASS';

EXIT;
```

Replace `NEUTRON_DBPASS` with a secure password.

## Creating the Neutron User in Keystone

Create the Neutron service user:

```bash
openstack user create --domain default --password-prompt neutron
```

Output:

```
+---------------------+----------------------------------+
| Field               | Value                            |
+---------------------+----------------------------------+
| domain_id           | default                          |
| enabled             | True                             |
| id                  | 212a57431d3743fea78c1a906ede2d6b |
| name                | neutron                          |
| options             | {}                               |
| password_expires_at | None                             |
+---------------------+----------------------------------+
```

Add the `service` role (not admin, despite earlier patterns):

```bash
openstack role add --project service --user neutron service
```

## Registering Neutron in the Service Catalog

Create the network service:

```bash
openstack service create --name neutron --description "OpenStack Networking" network
```

Output:

```
+-------------+----------------------------------+
| Field       | Value                            |
+-------------+----------------------------------+
| description | OpenStack Networking             |
| enabled     | True                             |
| id          | cd90e9fc6ec04cd6af5f6a5b0c5dc32a |
| name        | neutron                          |
| type        | network                          |
+-------------+----------------------------------+
```

Create the endpoints:

```bash
openstack endpoint create --region RegionOne network public http://neutron:9696
openstack endpoint create --region RegionOne network internal http://neutron:9696
openstack endpoint create --region RegionOne network admin http://neutron:9696
```

Neutron listens on port 9696.

## Installing Neutron

Install Neutron packages:

```bash
sudo apt update
sudo apt install -y neutron-server \
  neutron-plugin-ml2 \
  neutron-linuxbridge-agent \
  neutron-dhcp-agent \
  neutron-metadata-agent \
  python3-neutronclient
```

These packages provide the API server, ML2 plugin, Linux Bridge agent, DHCP agent, and metadata agent.

## Generating Metadata Shared Secret

Nova and Neutron share a secret for metadata proxy authentication. Generate a random secret:

```bash
openssl rand -hex 10
```

Example output:

```
64d7e168c8cd214b5f91
```

Save this value for use in both Neutron and Nova configuration.

## Configuring Neutron

### Main Configuration: /etc/neutron/neutron.conf

Edit `/etc/neutron/neutron.conf`:

```bash
sudo nano /etc/neutron/neutron.conf
```

**[DEFAULT] Section**:

```ini
[DEFAULT]
core_plugin = ml2
transport_url = rabbit://neutron:RABBITMQ_PASS@keystone:5672
```

**[database] Section**:

```ini
[database]
connection = mysql+pymysql://neutron:NEUTRON_DBPASS@keystone/neutron
```

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
username = neutron
password = NEUTRON_DBPASS
```

**[nova] Section** (for Nova integration):

```ini
[nova]
auth_url = http://keystone:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = nova
password = NOVA_PASS
```

**[oslo_messaging_rabbit] Section**:

```ini
[oslo_messaging_rabbit]
transport_url = rabbit://neutron:RABBITMQ_PASS@keystone
rpc_response_timeout = 60
rabbit_login_method = PLAIN
```

### ML2 Plugin Configuration: /etc/neutron/plugins/ml2/ml2_conf.ini

Edit `/etc/neutron/plugins/ml2/ml2_conf.ini`:

```ini
[DEFAULT]
core_plugin = ml2
service_plugins = router
auth_strategy = keystone
allow_overlapping_ips = true
transport_url = rabbit://neutron:RABBITMQ_PASS@keystone

[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = linuxbridge,l2population
extension_drivers = port_security

[ml2_type_flat]
flat_networks = provider

[ml2_type_vxlan]
vni_ranges = 1:1000

[securitygroup]
enable_ipset = true
```

This configuration:
- Supports flat, VLAN, and VXLAN networks
- Uses VXLAN for tenant networks
- Uses Linux Bridge for L2 connectivity
- Enables port security and security groups

### Linux Bridge Agent Configuration: /etc/neutron/plugins/ml2/linuxbridge_agent.ini

Edit `/etc/neutron/plugins/ml2/linuxbridge_agent.ini`:

```ini
[DEFAULT]
transport_url = rabbit://neutron:RABBITMQ_PASS@keystone

[linux_bridge]
physical_interface_mappings = provider:enp0s8

[vxlan]
enable_vxlan = true
local_ip = 192.168.56.106
l2_population = true

[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
```

**Important**: `physical_interface_mappings = provider:enp0s8` maps the `provider` network to the physical interface `enp0s8` (the host-only adapter). Adjust `enp0s8` if your interface name differs.

The `local_ip` is the Neutron node's IP address on the management network (192.168.56.106).

### Metadata Agent Configuration: /etc/neutron/metadata_agent.ini

Edit `/etc/neutron/metadata_agent.ini`:

```ini
[DEFAULT]
nova_metadata_host = nova
nova_metadata_protocol = http
nova_metadata_port = 8775
metadata_proxy_shared_secret = 64d7e168c8cd214b5f91
metadata_workers = 4
nova_metadata_insecure = False

[agent]
root_helper = sudo neutron-rootwrap /etc/neutron/rootwrap.conf
```

Replace the `metadata_proxy_shared_secret` with the value generated earlier.

## Configuring Nova for Neutron Integration

On the Nova node, edit `/etc/nova/nova.conf`:

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

Restart Nova services on the Nova node:

```bash
sudo systemctl restart nova-api nova-compute
```

## Fixing Eventlet Monkey-Patching

Similar to Nova, Neutron requires eventlet monkey-patching. Edit `/usr/bin/neutron-server`:

```python
#!/usr/bin/python3
# PBR Generated from 'console_scripts'
import eventlet
eventlet.monkey_patch()

import sys

from neutron.cmd.eventlet.server import main

if __name__ == "__main__":
    sys.exit(main())
```

Add the `eventlet.monkey_patch()` call after the shebang.

## Initializing the Neutron Database

Populate the Neutron database:

```bash
sudo -u neutron neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head
```

Output shows database migrations:

```
INFO  [alembic.runtime.migration] Context impl MySQLImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
  Running upgrade for neutron ...
INFO  [alembic.runtime.migration] Running upgrade  -> kilo
...
INFO  [alembic.runtime.migration] Running upgrade 76df7844a8c6 -> 1ffef8d6f371
INFO  [alembic.runtime.migration] Running upgrade 1ffef8d6f371 -> 8160f7a9cebb
  OK
```

## Starting Neutron Services

Enable and start Neutron services:

```bash
sudo systemctl enable neutron-server neutron-linuxbridge-agent neutron-metadata-agent neutron-dhcp-agent
sudo systemctl start neutron-server neutron-linuxbridge-agent neutron-metadata-agent neutron-dhcp-agent
```

Verify services are running:

```bash
sudo systemctl status neutron-server
sudo systemctl status neutron-linuxbridge-agent
sudo systemctl status neutron-metadata-agent
sudo systemctl status neutron-dhcp-agent
```

## Verifying Neutron Operation

Check Neutron endpoints are registered:

```bash
openstack endpoint list | grep neutron
```

Output:

```
| 40daa67e... | RegionOne | neutron | network | True | internal | http://neutron:9696 |
| 5246b0f5... | RegionOne | neutron | network | True | admin    | http://neutron:9696 |
| c4f58d29... | RegionOne | neutron | network | True | public   | http://neutron:9696 |
```

Check Neutron agents are alive:

```bash
openstack network agent list
```

Output:

```
+--------------------------------------+--------------------+---------+-------------------+-------+-------+---------------------------+
| ID                                   | Agent Type         | Host    | Availability Zone | Alive | State | Binary                    |
+--------------------------------------+--------------------+---------+-------------------+-------+-------+---------------------------+
| 5ded5a1a-...                         | Linux bridge agent | neutron | None              | :-)   | UP    | neutron-linuxbridge-agent |
| bf951bf7-...                         | Metadata agent     | neutron | None              | :-)   | UP    | neutron-metadata-agent    |
+--------------------------------------+--------------------+---------+-------------------+-------+-------+---------------------------+
```

All agents should show `Alive: :-)` and `State: UP`.

## Creating Networks

With Neutron operational, create networks for instances.

### Create a Provider Network

The provider network connects instances to the external network (host-only adapter):

```bash
openstack network create --share --external \
  --provider-physical-network provider \
  --provider-network-type flat provider
```

Output:

```
+---------------------------+--------------------------------------+
| Field                     | Value                                |
+---------------------------+--------------------------------------+
| admin_state_up            | UP                                   |
| id                        | 5adf529a-8fbd-46c2-86b7-0b993d393219 |
| mtu                       | 1500                                 |
| name                      | provider                             |
| provider:network_type     | flat                                 |
| provider:physical_network | provider                             |
| router:external           | External                             |
| shared                    | True                                 |
| status                    | ACTIVE                               |
+---------------------------+--------------------------------------+
```

The `--external` flag marks this as an external network. The `--share` flag makes it available to all tenants.

### Create a Subnet on the Provider Network

Define an IP range matching the VirtualBox host-only network:

```bash
openstack subnet create --network provider \
  --allocation-pool start=192.168.56.150,end=192.168.56.200 \
  --dns-nameserver 8.8.8.8 \
  --gateway 192.168.56.1 \
  --subnet-range 192.168.56.0/24 \
  provider-subnet
```

Output:

```
+----------------------+--------------------------------------+
| Field                | Value                                |
+----------------------+--------------------------------------+
| allocation_pools     | 192.168.56.150-192.168.56.200        |
| cidr                 | 192.168.56.0/24                      |
| dns_nameservers      | 8.8.8.8                              |
| enable_dhcp          | True                                 |
| gateway_ip           | 192.168.56.1                         |
| id                   | 79019ca4-56ad-463a-90b3-b6fee09fd3c1 |
| ip_version           | 4                                    |
| name                 | provider-subnet                      |
| network_id           | 5adf529a-8fbd-46c2-86b7-0b993d393219 |
+----------------------+--------------------------------------+
```

This subnet:
- Allocates IPs from 192.168.56.150 to 192.168.56.200
- Uses 8.8.8.8 as the DNS server
- Sets the gateway to 192.168.56.1 (VirtualBox host-only adapter gateway)
- Enables DHCP for automatic IP assignment

### Create a Tenant Self-Service Network (Optional)

For multi-tenant isolation, create a private network using VXLAN:

```bash
openstack network create selfservice
```

Output:

```
+---------------------------+--------------------------------------+
| Field                     | Value                                |
+---------------------------+--------------------------------------+
| admin_state_up            | UP                                   |
| id                        | 26550183-c942-49cb-921f-c3ef64d9ef78 |
| mtu                       | 1450                                 |
| name                      | selfservice                          |
| provider:network_type     | vxlan                                |
| provider:segmentation_id  | 201                                  |
| router:external           | Internal                             |
| status                    | ACTIVE                               |
+---------------------------+--------------------------------------+
```

The network uses VXLAN with segmentation ID 201, providing isolation from other tenants.

### Verify Networks

List all networks:

```bash
openstack network list
```

Output:

```
+--------------------------------------+-------------+--------------------------------------+
| ID                                   | Name        | Subnets                              |
+--------------------------------------+-------------+--------------------------------------+
| 26550183-c942-49cb-921f-c3ef64d9ef78 | selfservice |                                      |
| 5adf529a-8fbd-46c2-86b7-0b993d393219 | provider    | 79019ca4-56ad-463a-90b3-b6fee09fd3c1 |
+--------------------------------------+-------------+--------------------------------------+
```

List subnets:

```bash
openstack subnet list
```

Output:

```
+--------------------------------------+------------------+--------------------------------------+-------------------+
| ID                                   | Name             | Network                              | Subnet            |
+--------------------------------------+------------------+--------------------------------------+-------------------+
| 79019ca4-56ad-463a-90b3-b6fee09fd3c1 | provider-subnet  | 5adf529a-8fbd-46c2-86b7-0b993d393219 | 192.168.56.0/24   |
+--------------------------------------+------------------+--------------------------------------+-------------------+
```

## Common Issues and Troubleshooting

### Agents Show XXX in Alive Column

If `openstack network agent list` shows `XXX` instead of `:-)`:

1. **Check service status**:
   ```bash
   sudo systemctl status neutron-linuxbridge-agent
   sudo systemctl status neutron-metadata-agent
   ```

2. **Check logs**:
   ```bash
   sudo journalctl -u neutron-linuxbridge-agent -n 50
   sudo tail -f /var/log/neutron/neutron-linuxbridge-agent.log
   ```

3. **Verify RabbitMQ connection**:
   ```bash
   sudo rabbitmqctl list_connections
   ```

4. **Restart services**:
   ```bash
   sudo systemctl restart neutron-linuxbridge-agent neutron-metadata-agent
   ```

### Inconsistent transport_url Settings

Check all Neutron config files have consistent RabbitMQ credentials:

```bash
sudo grep -r "transport_url" /etc/neutron/
```

Ensure all references use the same username (either `neutron` or `openstack`) and password.

### RabbitMQ Authentication Failures

Verify RabbitMQ credentials from the Keystone node:

```bash
sudo rabbitmqctl authenticate_user neutron RABBITMQ_PASS
sudo rabbitmqctl authenticate_user openstack RABBITMQ_PASS
```

Both should show `Success`.

### Network Creation Failures

If network creation fails:

1. **Check neutron-server logs**:
   ```bash
   sudo tail -f /var/log/neutron/neutron-server.log
   ```

2. **Verify ML2 plugin is loaded**:
   ```bash
   neutron-db-manage --config-file /etc/neutron/neutron.conf current
   ```

3. **Check physical interface exists**:
   ```bash
   ip link show enp0s8
   ```

### Metadata Service Failures

If instances can't retrieve metadata:

- Verify metadata secret matches in both `/etc/neutron/metadata_agent.ini` and `/etc/nova/nova.conf`
- Check metadata agent is running: `sudo systemctl status neutron-metadata-agent`
- Verify Nova metadata service is accessible: `curl http://nova:8775`

### Restarting All Neutron Services

```bash
sudo systemctl restart neutron-server neutron-linuxbridge-agent neutron-metadata-agent neutron-dhcp-agent
```

## What's Next

With Neutron operational and networks created, instances can now connect to the network. The next post covers Horizon, the web-based dashboard for managing OpenStack resources through a graphical interface.

## Summary

This post covered:

- Neutron's role in providing virtual networking
- Network types (flat, VLAN, VXLAN) and architecture
- Cloning the Neutron VM
- Creating the Neutron database
- Creating the Neutron service user in Keystone
- Registering Neutron in the service catalog
- Installing Neutron packages (server, ML2 plugin, Linux Bridge agent, DHCP agent, metadata agent)
- Configuring Neutron with database, RabbitMQ, and Keystone integration
- Configuring the ML2 plugin and Linux Bridge agent
- Configuring Nova for Neutron integration
- Initializing the Neutron database
- Verifying Neutron agents are operational
- Creating provider and self-service networks
- Creating subnets with DHCP and gateway configuration
- Troubleshooting agent connectivity and RabbitMQ issues

Neutron is now providing virtual networking for OpenStack instances. In the next post, we'll install Horizon to provide a web-based interface for managing the entire OpenStack environment.
