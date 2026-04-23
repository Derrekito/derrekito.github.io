---
title: "OpenStack RabbitMQ: Message Queue for Service Communication"
date: 2026-10-26
categories: [Cloud Computing, Infrastructure]
tags: [openstack, rabbitmq, message-queue, amqp, messaging, distributed-systems]
---

RabbitMQ provides asynchronous message passing between OpenStack services. While services use synchronous REST APIs for direct requests, many operations require notification of state changes or coordination between components. RabbitMQ handles this communication pattern, enabling services to publish and consume messages without direct coupling.

This post covers RabbitMQ installation on the Keystone node, configuration for OpenStack services, and common troubleshooting scenarios.

## Why OpenStack Needs Message Queuing

OpenStack services are distributed and event-driven. Consider launching a virtual machine:

1. Nova API receives the request
2. Nova scheduler determines which compute host should run the instance
3. Nova compute on the selected host creates the VM
4. Neutron provisions networking
5. Cinder attaches volumes if requested
6. All services update their state

Without a message queue, Nova API would need to poll each service or maintain persistent connections. RabbitMQ decouples this communication: services publish messages to exchanges, and interested services consume from queues. This pattern enables:

- **Asynchronous operations**: Services don't block waiting for responses
- **Load distribution**: Multiple workers can consume from the same queue
- **Fault tolerance**: Messages persist if a consumer is temporarily unavailable
- **Loose coupling**: Services don't need to know about each other's locations

## RabbitMQ Architecture

RabbitMQ implements the Advanced Message Queuing Protocol (AMQP). Key concepts:

- **Producer**: Service that sends messages (e.g., Nova API)
- **Exchange**: Routes messages to queues based on routing keys
- **Queue**: Stores messages until consumed
- **Consumer**: Service that receives messages (e.g., Nova compute)
- **Binding**: Links an exchange to a queue with routing rules
- **Virtual host (vhost)**: Namespace for isolation (similar to databases)

OpenStack uses the default vhost `/` and creates users for each service that needs messaging.

## Installing RabbitMQ on Keystone Node

RabbitMQ runs on the Keystone node to keep the deployment compact. In production environments, RabbitMQ often runs on dedicated nodes with clustering for high availability.

### Prerequisites

Ensure you're on the Keystone VM:

```bash
ssh openstack@keystone
```

### Install RabbitMQ

Install the RabbitMQ server package:

```bash
sudo apt-get install rabbitmq-server -y
```

Some guides recommend installing Erlang explicitly, though it's typically pulled in as a dependency:

```bash
sudo apt install gnupg erlang -y
```

Enable and start RabbitMQ:

```bash
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server
```

Verify RabbitMQ is running:

```bash
sudo systemctl status rabbitmq-server
```

Expected output includes:

```
● rabbitmq-server.service - RabbitMQ broker
   Loaded: loaded (/lib/systemd/system/rabbitmq-server.service; enabled)
   Active: active (running)
```

## Creating RabbitMQ Users for OpenStack

Each OpenStack service needs credentials to access RabbitMQ. Create a general `openstack` user that most services will use:

```bash
sudo rabbitmqctl add_user openstack RABBITMQ_PASS
```

Replace `RABBITMQ_PASS` with a secure password. For this learning environment, a simple placeholder works.

Set permissions for the `openstack` user:

```bash
sudo rabbitmqctl set_permissions openstack ".*" ".*" ".*"
```

The three `".*"` patterns grant permissions for:
1. **Configure**: Create and delete queues and exchanges
2. **Write**: Publish messages
3. **Read**: Consume messages

These permissions apply to all resources matching the pattern `.*` (everything) in the default vhost.

### Optional: Create Service-Specific Users

Some deployments create separate users per service (Nova, Neutron, etc.) for finer-grained access control. Create a Neutron-specific user:

```bash
sudo rabbitmqctl add_user neutron RABBITMQ_PASS
sudo rabbitmqctl set_permissions neutron ".*" ".*" ".*"
```

This approach isolates service credentials but requires configuring each service with its own RabbitMQ user. For simplicity, this series primarily uses the `openstack` user.

## Enabling the Management Plugin

RabbitMQ includes a web-based management interface for monitoring queues, exchanges, and message rates. Enable the management plugin:

```bash
sudo rabbitmq-plugins enable rabbitmq_management
```

Output:

```
Enabling plugins on node rabbit@keystone:
rabbitmq_management
The following plugins have been configured:
  rabbitmq_management
  rabbitmq_management_agent
  rabbitmq_web_dispatch
Applying plugin configuration to rabbit@keystone...
The following plugins have been enabled:
  rabbitmq_management
  rabbitmq_management_agent
  rabbitmq_web_dispatch

started 3 plugins.
```

The management interface is now accessible at `http://keystone:15672`. The default credentials are `guest`/`guest`, but this account only works from localhost. Use the `openstack` user created earlier to log in remotely.

## Configuring RabbitMQ for Remote Access

By default, RabbitMQ listens only on localhost. OpenStack services on other nodes need to connect, so configure RabbitMQ to accept remote connections.

Create or edit `/etc/rabbitmq/rabbitmq-env.conf`:

```bash
sudo nano /etc/rabbitmq/rabbitmq-env.conf
```

Set the node IP address to `0.0.0.0` to listen on all interfaces:

```ini
# Bind to all interfaces instead of localhost
NODE_IP_ADDRESS=0.0.0.0

# Default AMQP port
NODE_PORT=5672
```

Restart RabbitMQ to apply the configuration:

```bash
sudo systemctl restart rabbitmq-server
```

Verify RabbitMQ is listening on port 5672:

```bash
sudo ss -tulnp | grep 5672
```

Expected output:

```
tcp   LISTEN 0  128  0.0.0.0:5672  0.0.0.0:*  users:(("beam.smp",pid=1234,...))
```

## Configuring OpenStack Services to Use RabbitMQ

Each OpenStack service needs RabbitMQ connection information in its configuration file. The pattern is consistent across services.

### Nova Configuration

Edit `/etc/nova/nova.conf` on the Nova node:

```ini
[DEFAULT]
transport_url = rabbit://openstack:RABBITMQ_PASS@keystone:5672/

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

The `transport_url` is the primary connection string. The `[oslo_messaging_rabbit]` section provides additional tuning options:

- `rabbit_retry_interval`: Initial retry delay in seconds
- `rabbit_retry_backoff`: Multiplier for exponential backoff
- `rabbit_max_retries`: Maximum retry attempts (0 = infinite)

### Neutron Configuration

Edit `/etc/neutron/neutron.conf` on the Neutron node:

```ini
[DEFAULT]
core_plugin = ml2
transport_url = rabbit://neutron:RABBITMQ_PASS@controller

[experimental]
linuxbridge = True
```

If using the `neutron` user, update the credentials accordingly. The hostname `controller` resolves to the Keystone node (recall the alias added in `/etc/hosts`).

### Other Services

Glance, Cinder, and other services follow the same pattern. Each configuration file has a `transport_url` in the `[DEFAULT]` section pointing to RabbitMQ on the Keystone node.

## Verifying RabbitMQ Operation

### List Users

Check that the RabbitMQ users were created:

```bash
sudo rabbitmqctl list_users
```

Output:

```
Listing users ...
user          tags
rabbitmq      []
neutron       [administrator]
guest         [administrator]
openstack     [administrator]
```

The `administrator` tag grants full management access.

### Check Virtual Hosts

List virtual hosts:

```bash
sudo rabbitmqctl list_vhosts
```

Output:

```
Listing vhosts ...
/
```

The default vhost `/` is where OpenStack services communicate.

### Monitor Queue Activity

After services start using RabbitMQ, check queue creation and message flow:

```bash
sudo rabbitmqctl list_queues
```

Example output after Nova is running:

```
Timeout: 60.0 seconds ...
Listing queues for vhost / ...
name                             messages
conductor                        0
scheduler                        0
compute                          0
```

Queues appear as services register consumers.

### Access the Management Web UI

Navigate to `http://keystone:15672` in a browser (replace `keystone` with the VM's IP if hostname resolution doesn't work). Log in with the `openstack` user credentials.

The dashboard shows:
- Connection count
- Channel count
- Queue depth
- Message rates (incoming/outgoing)
- Consumer activity

This interface is invaluable for debugging message flow issues.

## Common Issues and Troubleshooting

### Password Reset

If you forget the RabbitMQ password or need to change it:

```bash
sudo rabbitmqctl change_password openstack NEW_PASSWORD
sudo rabbitmqctl change_password neutron NEW_PASSWORD
```

Update the corresponding OpenStack service configuration files with the new password and restart the services.

### Connection Refused Errors

If OpenStack services can't connect to RabbitMQ:

1. **Verify RabbitMQ is running**:
   ```bash
   sudo systemctl status rabbitmq-server
   ```

2. **Check RabbitMQ is listening on the correct interface**:
   ```bash
   sudo ss -tulnp | grep 5672
   ```

3. **Test connectivity from the client node**:
   ```bash
   telnet keystone 5672
   ```

4. **Verify hostname resolution**:
   ```bash
   ping keystone
   ```

5. **Check firewall rules** (if enabled):
   ```bash
   sudo ufw status
   ```

### Authentication Failures

If services authenticate but can't perform operations:

1. **Verify user permissions**:
   ```bash
   sudo rabbitmqctl list_permissions -p /
   ```

2. **Check password matches configuration**:
   Review `/etc/nova/nova.conf`, `/etc/neutron/neutron.conf`, etc.

3. **Examine RabbitMQ logs**:
   ```bash
   sudo tail -f /var/log/rabbitmq/rabbit@keystone.log
   ```

### High Memory Usage

RabbitMQ can consume significant memory if queues fill up. Monitor queue depths:

```bash
sudo rabbitmqctl list_queues name messages consumers
```

If messages accumulate without consumers:
- A service may be down
- A service may be slow to process messages
- Configuration may be incorrect (wrong queue name)

Restart the consuming service or investigate why it's not processing messages.

### Service Logs Show RabbitMQ Errors

Check the OpenStack service logs for RabbitMQ-related errors:

```bash
# Nova
sudo journalctl -u nova-compute -n 50

# Neutron
sudo journalctl -u neutron-server -n 50
```

Common error patterns:
- `Connection refused`: RabbitMQ isn't running or not listening on the right interface
- `Authentication failed`: Wrong username/password
- `NOT_FOUND`: Queue or exchange doesn't exist (service may not be running)

### Restarting RabbitMQ

If RabbitMQ becomes unresponsive:

```bash
sudo systemctl restart rabbitmq-server
```

Wait a few seconds for RabbitMQ to fully start, then restart dependent OpenStack services.

## Message Flow Example

When Nova launches an instance:

1. Nova API validates the request and publishes a message to the `scheduler` exchange
2. Nova scheduler consumes the message, selects a compute host, and publishes to the `compute.<hostname>` exchange
3. Nova compute on the selected host consumes the message and creates the VM
4. Nova compute publishes status updates back to the conductor

Each step is asynchronous. If a consumer is temporarily unavailable, messages wait in the queue until the consumer reconnects.

## What's Next

With RabbitMQ operational, OpenStack services can communicate asynchronously. The next post covers Glance, the image service that stores VM templates and snapshots. Glance uses RabbitMQ to notify Nova when images become available or change state.

## Summary

This post covered:

- Why OpenStack needs message queuing
- RabbitMQ architecture (exchanges, queues, consumers)
- Installing RabbitMQ on the Keystone node
- Creating RabbitMQ users for OpenStack services
- Enabling the management plugin for web-based monitoring
- Configuring RabbitMQ to accept remote connections
- Updating OpenStack service configurations to use RabbitMQ
- Verifying operation with `rabbitmqctl` commands
- Troubleshooting connection, authentication, and performance issues

RabbitMQ is now routing messages between OpenStack services. In the next post, we'll install Glance to manage virtual machine images.
