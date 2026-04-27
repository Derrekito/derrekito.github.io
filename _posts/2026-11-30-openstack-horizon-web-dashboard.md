---
title: "OpenStack Horizon: Web Dashboard for Cloud Management"
date: 2026-11-30
categories: [Cloud Computing, Infrastructure]
tags: [openstack, horizon, dashboard, web-ui, django, apache]
---

Horizon provides a web-based dashboard for OpenStack, enabling users to manage cloud resources through a graphical interface. Instead of memorizing CLI commands, administrators and users can provision instances, configure networks, manage volumes, and monitor usage from a browser. Horizon integrates with all OpenStack services, offering a unified view of the cloud environment.

This post covers Horizon installation on the Keystone node, configuration for multi-service integration, and accessing the dashboard.

## What Horizon Does

Horizon translates OpenStack API calls into an intuitive web interface:

1. **Instance Management**: Launch, stop, reboot, and delete instances
2. **Network Configuration**: Create networks, subnets, routers, and security groups
3. **Volume Management**: Create, attach, and manage block storage volumes
4. **Image Management**: Upload and manage VM images
5. **User Management**: Create projects, users, and assign roles (admin only)
6. **Resource Monitoring**: View quotas, usage statistics, and system health
7. **Access & Security**: Manage keypairs, security groups, and floating IPs

Horizon doesn't add new functionality—it provides a user-friendly frontend to existing OpenStack APIs.

### Horizon Architecture

Horizon is a Django web application running under Apache with mod_wsgi:

- **Django Framework**: Python web framework handling routing, templates, and logic
- **OpenStack Python Clients**: Libraries that communicate with OpenStack service APIs
- **Apache2 + mod_wsgi**: Serves the Django application
- **Memcached**: Caches session data and API responses for performance

When a user performs an action in Horizon (e.g., launch an instance), Horizon uses the Nova Python client to call the Nova API, which then processes the request.

### Benefits of the Web Interface

- **Accessibility**: No CLI knowledge required
- **Visual Feedback**: See resource status at a glance
- **Guided Workflows**: Step-by-step wizards for complex operations
- **Multi-User**: Simultaneous access from different locations
- **Cross-Platform**: Works on any device with a web browser

While advanced users often prefer the CLI for automation and scripting, the dashboard is invaluable for learning, troubleshooting, and ad-hoc management.

## Prerequisites

Before installing Horizon:

- Keystone operational (Horizon runs on the Keystone node)
- Memcached running on Keystone node
- Other OpenStack services (Nova, Neutron, Glance) operational for full functionality

## Installing Horizon on the Keystone Node

Horizon installs on the Keystone node to keep the deployment compact. SSH to the Keystone VM:

```bash
ssh openstack@keystone
```

Install the Horizon package:

```bash
sudo apt install -y openstack-dashboard
```

This installs Horizon, its dependencies (Django, Apache2 configuration), and creates the necessary directories.

## Configuring Horizon

Horizon configuration is in `/etc/openstack-dashboard/local_settings.py`, a Python configuration file for Django.

Edit the configuration file:

```bash
sudo nano /etc/openstack-dashboard/local_settings.py
```

### OpenStack Host

Set the hostname where Keystone runs:

```python
OPENSTACK_HOST = "keystone"
```

This tells Horizon where to find the identity service.

### Allowed Hosts

Configure which hostnames can access the dashboard:

```python
ALLOWED_HOSTS = ['*']
```

For production, restrict this to specific hostnames or IPs (e.g., `['192.168.56.103', 'keystone']`). Using `'*'` allows access from any host.

### Session Engine and Cache

Configure session storage and caching:

```python
SESSION_ENGINE = 'django.contrib.sessions.backends.cache'

CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
        'LOCATION': 'keystone:11211',
    }
}
```

This uses Memcached for session storage and API response caching, improving performance and reducing load on OpenStack services.

### Keystone Configuration

Set the Keystone API endpoint:

```python
OPENSTACK_KEYSTONE_URL = "http://%s:5000/identity/v3" % OPENSTACK_HOST
```

The `%s` substitutes `OPENSTACK_HOST` (keystone), creating `http://keystone:5000/identity/v3`.

Enable multi-domain support:

```python
OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True
```

This allows managing multiple domains from the dashboard.

### API Versions

Specify API versions for OpenStack services:

```python
OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 3,
}
```

This tells Horizon to use Identity v3, Glance v2, and Cinder v3 APIs.

### Default Domain and Role

Set default values for user creation:

```python
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = "Default"
OPENSTACK_KEYSTONE_DEFAULT_ROLE = "admin"
```

Users created through Horizon will belong to the "Default" domain with the "admin" role by default.

### Neutron Network Configuration

Configure Neutron features available in the dashboard:

```python
OPENSTACK_NEUTRON_NETWORK = {
    'enable_router': False,
    'enable_quotas': False,
    'enable_ipv6': False,
    'enable_distributed_router': False,
    'enable_ha_router': False,
    'enable_fip_topology_check': False,
}
```

This deployment disables advanced features like routers and floating IP topology checks. Production deployments typically enable these features.

Save and exit the configuration file.

## Configuring Apache2 for Horizon

Horizon runs as a WSGI application under Apache2. Edit the Apache configuration:

```bash
sudo nano /etc/apache2/conf-available/openstack-dashboard.conf
```

Add the following line to ensure proper WSGI application group handling:

```apache
WSGIApplicationGroup %{GLOBAL}
```

This directive prevents issues with multi-threaded WSGI applications.

Save and exit.

## Restarting Apache2

Restart Apache2 to load Horizon:

```bash
sudo systemctl restart apache2
```

Verify Apache2 is running:

```bash
sudo systemctl status apache2
```

Check Horizon is accessible:

```bash
curl http://keystone/dashboard
```

If Apache2 returns HTML, Horizon is running.

## Accessing the Horizon Dashboard

Open a web browser on your host machine and navigate to:

```
http://192.168.56.103/dashboard
```

Or use the hostname if DNS is configured:

```
http://keystone/dashboard
```

You should see the Horizon login page.

### Logging In

Use the admin credentials created during Keystone installation:

- **Username**: `admin`
- **Password**: `KEYSTONE_DBPASS` (or whatever password was set during bootstrap)
- **Domain**: `Default`

After logging in, the dashboard displays the OpenStack overview showing:

- Active instances
- Available VCPUs
- Used RAM
- Available volumes
- Active networks

## Navigating the Dashboard

Horizon organizes functionality into panels:

### Project Tab

User-level operations for managing resources within a project:

- **Compute**
  - Instances: Launch, manage VMs
  - Images: View available images
  - Flavors: View instance sizes
  - Keypairs: Manage SSH keys

- **Network**
  - Networks: Create and manage virtual networks
  - Routers: Configure routing (if enabled)
  - Security Groups: Define firewall rules
  - Floating IPs: Assign public IPs (if enabled)

- **Volumes**
  - Volumes: Create and attach block storage
  - Snapshots: Create volume snapshots

### Admin Tab

Administrative operations for managing the cloud:

- **Compute**
  - Hypervisors: View compute node status
  - Instances: View all instances across all projects
  - Flavors: Create and manage instance sizes

- **Network**
  - Networks: View and manage all networks
  - Routers: View all routers

- **System**
  - Services: View OpenStack service status
  - System Information: View hypervisor and service details

- **Identity**
  - Domains: Manage identity domains
  - Projects: Create and manage projects
  - Users: Create and manage user accounts
  - Roles: Assign roles to users

### Settings

User preferences and password management.

## Using Horizon: Example Workflows

### Viewing Compute Services

1. Navigate to **Admin → System → System Information**
2. Click the **Compute Services** tab
3. View Nova services (scheduler, conductor, compute) and their status

This shows the same information as `openstack compute service list`.

### Viewing Network Agents

1. Navigate to **Admin → System → System Information**
2. Click the **Network Agents** tab
3. View Neutron agents (Linux Bridge, metadata, DHCP) and their health

This shows the same information as `openstack network agent list`.

### Viewing Images

1. Navigate to **Project → Compute → Images**
2. View available images (CirrOS, Ubuntu)
3. Click an image to see details (size, format, status)

### Creating a Network (If Router Enabled)

1. Navigate to **Project → Network → Networks**
2. Click **Create Network**
3. Enter network name and subnet details
4. Click **Create**

## Common Issues and Troubleshooting

### Dashboard Shows 404 Not Found

If accessing `http://keystone/dashboard` returns 404:

1. **Verify Apache2 is running**:
   ```bash
   sudo systemctl status apache2
   ```

2. **Check Horizon configuration is enabled**:
   ```bash
   ls /etc/apache2/conf-enabled/ | grep dashboard
   ```

3. **Enable the configuration if missing**:
   ```bash
   sudo a2enconf openstack-dashboard
   sudo systemctl restart apache2
   ```

### Login Fails with "Unable to Authenticate"

If login fails:

1. **Verify credentials** are correct (username, password, domain)

2. **Check Keystone is accessible from Keystone node**:
   ```bash
   openstack token issue
   ```

3. **Verify `OPENSTACK_KEYSTONE_URL` in `/etc/openstack-dashboard/local_settings.py`** is correct

4. **Check Apache error logs**:
   ```bash
   sudo tail -f /var/log/apache2/error.log
   ```

### Dashboard is Slow or Unresponsive

If the dashboard is sluggish:

1. **Check Memcached is running**:
   ```bash
   sudo systemctl status memcached
   ```

2. **Verify Memcached connection in Horizon configuration**:
   ```python
   CACHES = {
       'default': {
           'LOCATION': 'keystone:11211',
       }
   }
   ```

3. **Clear Memcached cache**:
   ```bash
   echo 'flush_all' | nc keystone 11211
   ```

4. **Restart Apache2**:
   ```bash
   sudo systemctl restart apache2
   ```

### Service Tabs Show Empty or Errors

If service panels show errors:

1. **Verify services are running** (Nova, Neutron, Glance, Cinder):
   ```bash
   openstack compute service list
   openstack network agent list
   openstack image list
   ```

2. **Check service endpoints are registered**:
   ```bash
   openstack endpoint list
   ```

3. **Review Horizon logs**:
   ```bash
   sudo tail -f /var/log/apache2/error.log
   ```

### Permission Errors in Dashboard

If certain operations fail with permission errors:

- Verify the user has appropriate roles assigned
- Check project membership for the user
- Verify Keystone policy files allow the operation

## Security Considerations

For production deployments:

1. **Restrict ALLOWED_HOSTS**:
   ```python
   ALLOWED_HOSTS = ['horizon.example.com', '192.168.56.103']
   ```

2. **Enable HTTPS**:
   - Configure Apache SSL certificate
   - Force HTTPS redirects
   - Set `SECURE_PROXY_SSL_HEADER` in Horizon config

3. **Use SECRET_KEY**:
   ```python
   SECRET_KEY = 'random-secret-generated-string'
   ```

4. **Disable DEBUG mode**:
   ```python
   DEBUG = False
   ```

5. **Implement session timeout**:
   ```python
   SESSION_TIMEOUT = 3600  # 1 hour
   ```

## What's Next

With Horizon operational, OpenStack is fully accessible via web interface. The next post covers Cinder, the block storage service that provides persistent volumes for instances.

## Summary

This post covered:

- Horizon's role as a web-based management interface
- Django architecture and Apache2 integration
- Installing Horizon on the Keystone node
- Configuring Horizon for multi-service integration
- Setting Keystone URL, caching, and API versions
- Configuring Neutron features in the dashboard
- Apache2 WSGI configuration
- Accessing the dashboard via web browser
- Logging in with admin credentials
- Navigating the Project and Admin tabs
- Viewing compute services and network agents
- Troubleshooting login failures, performance issues, and service errors
- Security considerations for production deployments

Horizon is now providing a graphical interface for managing OpenStack. In the next post, we'll install Cinder to provide persistent block storage for instances.
