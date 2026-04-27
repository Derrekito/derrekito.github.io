---
title: "OpenStack Keystone: Identity and Authentication Service"
date: 2026-10-19
categories: [Cloud Computing, Infrastructure]
tags: [openstack, keystone, authentication, identity, access-control, mariadb]
---

Keystone is OpenStack's identity service, providing authentication (authN) and authorization (authZ) for all OpenStack components. Every API request to OpenStack services passes through Keystone for validation. It manages user credentials, service catalogs, and role-based access controls, enabling secure and centralized identity management across the entire cloud infrastructure.

This post covers Keystone installation, configuration, and demonstrates creating domains, projects, users, and roles.

## What Keystone Does

Keystone serves three primary functions:

1. **Authentication**: Verifies user credentials and issues tokens for API access
2. **Service Catalog**: Maintains a registry of available services and their API endpoints
3. **Authorization**: Enforces role-based access control (RBAC) for resources

When a user or service wants to interact with OpenStack (launch an instance, create a volume, etc.), they first authenticate with Keystone to receive a token. This token accompanies all subsequent API requests, proving the caller's identity and permissions.

### Key Concepts

- **Domain**: A container for projects, users, and groups. The `default` domain exists by default.
- **Project**: A container for resources (instances, volumes, networks). Previously called "tenant."
- **User**: An identity that can authenticate and receive tokens.
- **Role**: Defines permissions. Users are assigned roles within projects.
- **Token**: A temporary credential issued after successful authentication.
- **Service**: An OpenStack component (Nova, Glance, etc.) registered in the catalog.
- **Endpoint**: An API URL where a service can be reached (public, internal, admin).

Keystone supports multiple authentication backends including SQL, LDAP, and external identity providers. This deployment uses the SQL backend with MariaDB.

## Prerequisites

Before installing Keystone, ensure you have:

- Completed the base VM setup from Part 1
- VirtualBox host-only network configured
- MariaDB installed and configured on the base VM
- OpenStack repository added

## Cloning the Keystone VM

Clone the base VM in VirtualBox:

1. Right-click **BaseVM** in VirtualBox
2. Select **Clone**
3. Name: `Keystone`
4. MAC Address Policy: **Generate new MAC addresses for all network adapters**
5. Clone type: **Full clone**
6. Click **Clone**

Start the Keystone VM and log in.

## Configuring the Keystone VM

Update the network configuration to assign the Keystone-specific IP address:

```bash
# Update Netplan to set static IP to 192.168.56.103
sudo sed -i 's/192\.168\.56\.10[0-9]\/24/192.168.56.103\/24/' /etc/netplan/*

# Apply the configuration
sudo netplan apply

# Update hostname
sudo hostnamectl set-hostname keystone

# Add 'controller' alias to localhost (Keystone also acts as the controller node)
sudo sed -i '/127.0.0.1 localhost/ s/$/ controller/' /etc/hosts
```

The `controller` alias is important because many OpenStack services reference `http://controller:5000` for Keystone authentication. By aliasing localhost to controller, services running on this VM can find Keystone locally.

Verify the network configuration:

```bash
ip addr show enp0s8
```

Expected output should show `192.168.56.103/24`.

Test SSH from the host machine:

```bash
ssh openstack@keystone
```

## Creating the Keystone Database

Keystone stores users, projects, roles, and service catalog information in a database. Create a dedicated MariaDB database:

```bash
# Connect to MariaDB
mysql -p
```

In the MariaDB prompt:

```sql
CREATE DATABASE keystone;

-- Grant privileges to keystone user from localhost
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'KEYSTONE_DBPASS';

-- Grant privileges from any host (for multi-node setups)
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'KEYSTONE_DBPASS';

-- Exit
EXIT;
```

Replace `KEYSTONE_DBPASS` with a secure password. For this learning environment, the simple placeholder is sufficient.

Verify the database was created:

```bash
mysql -p -e "SHOW DATABASES;"
```

You should see `keystone` in the list.

## Installing Keystone

Install the Keystone package:

```bash
sudo apt install -y keystone
```

This installs Keystone and its dependencies, including Apache2 (which serves the Keystone API via WSGI).

## Configuring Keystone

Edit the Keystone configuration file at `/etc/keystone/keystone.conf`:

```bash
sudo nano /etc/keystone/keystone.conf
```

### Database Connection

Find the `[database]` section and set the connection string:

```ini
[database]
connection = mysql+pymysql://keystone:KEYSTONE_DBPASS@localhost/keystone
```

This tells Keystone to connect to the MariaDB database created earlier.

### Token Provider

Find the `[token]` section and configure the Fernet token provider:

```ini
[token]
provider = fernet
```

Fernet tokens are lightweight, secure, and don't require persistence in the database. They contain encrypted credential information and can be validated without database lookups.

Save and exit the configuration file.

## Initializing Keystone

### Populate the Database

Synchronize the Keystone database schema:

```bash
# Set ownership of log directory
sudo chown -R keystone:keystone /var/log/keystone

# Allow keystone user to login temporarily (needed for db_sync)
sudo usermod -s /bin/bash keystone

# Set a password for the keystone system user
sudo passwd keystone

# Run database synchronization as keystone user
sudo -u keystone keystone-manage db_sync
```

The `db_sync` command creates all necessary tables in the Keystone database.

### Initialize Fernet Keys

Fernet tokens require cryptographic keys for encryption and validation:

```bash
sudo keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
sudo keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
```

Verify the keys were created:

```bash
sudo ls /etc/keystone/fernet-keys/
sudo ls /etc/keystone/credential-keys/
```

You should see numbered key files in both directories.

### Bootstrap Keystone

Bootstrap Keystone to create the initial admin user, service, and endpoints:

```bash
sudo keystone-manage bootstrap \
  --bootstrap-password KEYSTONE_DBPASS \
  --bootstrap-admin-url http://controller:5000/v3/ \
  --bootstrap-internal-url http://controller:5000/v3/ \
  --bootstrap-public-url http://controller:5000/v3/ \
  --bootstrap-region-id RegionOne
```

This command:
- Creates the `admin` user with password `KEYSTONE_DBPASS`
- Creates the `admin` role and `admin` project
- Registers the Keystone service in the catalog
- Creates three endpoints: admin, internal, and public (all point to the same URL in this deployment)
- Assigns the deployment to region `RegionOne`

## Configuring Apache2

Keystone runs as a WSGI application under Apache2. Configure Apache to recognize the controller hostname:

```bash
echo 'ServerName controller' | sudo tee -a /etc/apache2/apache2.conf
```

Restart Apache2 to apply changes:

```bash
sudo systemctl restart apache2
```

Verify Apache2 is running:

```bash
sudo systemctl status apache2
```

## Configuring MariaDB for Remote Access

If other OpenStack services will run on separate VMs (they will), MariaDB needs to accept remote connections. Edit `/etc/mysql/mariadb.conf.d/50-server.cnf`:

```bash
sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf
```

Find the `bind-address` line and change it from `127.0.0.1` to `0.0.0.0`:

```ini
bind-address = 0.0.0.0
```

This allows MariaDB to accept connections from any IP address. In a production environment, restrict this to the OpenStack management network.

Restart MariaDB:

```bash
sudo systemctl restart mariadb
```

## Testing Keystone Authentication

Set the environment variables for authentication:

```bash
export OS_USERNAME=admin
export OS_PASSWORD=KEYSTONE_DBPASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
```

Request a token from Keystone:

```bash
openstack token issue
```

Expected output:

```
+------------+----------------------------------+
| Field      | Value                            |
+------------+----------------------------------+
| expires    | 2026-10-19T12:34:56+0000        |
| id         | gAAAAABmKj... (long token)       |
| project_id | a1b2c3d4...                      |
| user_id    | e5f6g7h8...                      |
+------------+----------------------------------+
```

If the token is issued successfully, Keystone is working correctly.

## Demonstrating Keystone: Creating Resources

With Keystone running, create domains, projects, users, and roles to demonstrate its functionality.

### Create a Domain

Domains provide namespace isolation for projects and users:

```bash
openstack domain create --description "An Example Domain" example
```

Output:

```
+-------------+----------------------------------+
| Field       | Value                            |
+-------------+----------------------------------+
| description | An Example Domain                |
| enabled     | True                             |
| id          | 9a3784b804b549fa8ad142be9d0ff78e |
| name        | example                          |
| options     | {}                               |
| tags        | []                               |
+-------------+----------------------------------+
```

### Create Projects

Projects group resources. Create a `service` project for OpenStack services and a `myproject` project for demonstration:

```bash
openstack project create --domain default --description "Service Project" service
```

Output:

```
+-------------+----------------------------------+
| Field       | Value                            |
+-------------+----------------------------------+
| description | Service Project                  |
| domain_id   | default                          |
| enabled     | True                             |
| id          | be58db082a2644369e44d643b86d1286 |
| is_domain   | False                            |
| name        | service                          |
| options     | {}                               |
| parent_id   | default                          |
| tags        | []                               |
+-------------+----------------------------------+
```

Create a demo project:

```bash
openstack project create --domain default --description "Demo Project" myproject
```

Output:

```
+-------------+----------------------------------+
| Field       | Value                            |
+-------------+----------------------------------+
| description | Demo Project                     |
| domain_id   | default                          |
| enabled     | True                             |
| id          | 7301089091e940d3948bcf1629683309 |
| is_domain   | False                            |
| name        | myproject                        |
| options     | {}                               |
| parent_id   | default                          |
| tags        | []                               |
+-------------+----------------------------------+
```

### Create a User

Create a demo user:

```bash
openstack user create --domain default --password-prompt demo
```

You'll be prompted to enter a password twice. After creation:

```
+---------------------+----------------------------------+
| Field               | Value                            |
+---------------------+----------------------------------+
| domain_id           | default                          |
| enabled             | True                             |
| id                  | e32b40b0f63f4afa951e615878462a93 |
| name                | demo                             |
| options             | {}                               |
| password_expires_at | None                             |
+---------------------+----------------------------------+
```

List all users:

```bash
openstack user list
```

Output:

```
+----------------------------------+-------+
| ID                               | Name  |
+----------------------------------+-------+
| 24c7f0759f514d3f8a777f4f032cf4f6 | admin |
| e32b40b0f63f4afa951e615878462a93 | demo  |
+----------------------------------+-------+
```

### Create a Role and Assign It

Create a custom role:

```bash
openstack role create demorole
```

Output:

```
+-------------+----------------------------------+
| Field       | Value                            |
+-------------+----------------------------------+
| description | None                             |
| domain_id   | None                             |
| id          | ff86bd7c99e54133acef0d6f1e925c20 |
| name        | demorole                         |
| options     | {}                               |
+-------------+----------------------------------+
```

Assign the `demorole` role to the `demo` user in the `myproject` project:

```bash
openstack role add --project myproject --user demo demorole
```

This command produces no output on success.

List all roles:

```bash
openstack role list
```

Output:

```
+----------------------------------+----------+
| ID                               | Name     |
+----------------------------------+----------+
| 0d13cca7c3624bd6a2f3ed73677f801a | manager  |
| 98c3588507a84ebfb999facef2e5bc13 | reader   |
| a4867000a8a54b388f49d6d69de2829e | admin    |
| f4819b97bc154576bc034df13649090c | service  |
| fde9763d7bba44e6b826f3760221cb90 | member   |
| ff86bd7c99e54133acef0d6f1e925c20 | demorole |
+----------------------------------+----------+
```

The `admin`, `member`, `reader`, `manager`, and `service` roles are created automatically during bootstrap.

## Verifying Service Catalog

Check the service catalog to confirm Keystone is registered:

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
+-----------+-----------+-----------------------------------------+
```

This confirms Keystone is accessible at `http://controller:5000/v3/` and ready to authenticate other services.

## Common Issues and Troubleshooting

### Apache2 Not Starting

If Apache2 fails to start, check the error log:

```bash
sudo journalctl -u apache2 -n 50
```

Common issues:
- Port 5000 already in use
- Missing WSGI module
- Incorrect permissions on `/etc/keystone/`

### Database Connection Failures

If Keystone can't connect to MariaDB:

- Verify the database password in `/etc/keystone/keystone.conf` matches the password set during database creation
- Check MariaDB is running: `sudo systemctl status mariadb`
- Test connection manually: `mysql -u keystone -p keystone`

### Token Issue Failures

If `openstack token issue` fails:

- Verify environment variables are set correctly
- Check Apache2 is running: `sudo systemctl status apache2`
- Examine Keystone logs: `sudo tail -f /var/log/keystone/keystone.log`
- Confirm endpoints are registered: `openstack catalog list`

### "Unable to Establish Connection" Error

If services can't reach Keystone:

- Verify the hostname `controller` resolves to the correct IP
- Check `/etc/hosts` contains the mapping
- Test connectivity: `ping controller`
- Ensure firewall allows port 5000

## What's Next

With Keystone operational, the foundation is in place for the rest of OpenStack. Every subsequent service will:

1. Create a database in MariaDB
2. Create a service user in Keystone
3. Register the service in the Keystone catalog
4. Use Keystone tokens for inter-service communication

The next post covers RabbitMQ, the message queue that enables asynchronous communication between OpenStack services.

## Summary

This post covered:

- Cloning the Keystone VM from the base template
- Configuring networking and hostname
- Creating the Keystone database in MariaDB
- Installing and configuring Keystone
- Initializing Fernet keys for token encryption
- Bootstrapping Keystone with the admin user and endpoints
- Configuring Apache2 to serve the Keystone API
- Testing authentication with `openstack token issue`
- Creating domains, projects, users, and roles
- Verifying the service catalog

Keystone is now authenticating requests and ready to support additional OpenStack services. In the next post, we'll install RabbitMQ for message-based communication between services.
