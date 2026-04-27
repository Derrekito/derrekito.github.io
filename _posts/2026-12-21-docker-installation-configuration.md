---
title: "Docker Installation and Configuration for Container Deployments"
date: 2026-12-21
categories: [Cloud Computing, Containers]
tags: [docker, containers, virtualization, docker-compose, mongodb, containerization]
---

Docker simplifies application deployment by packaging software and dependencies into lightweight, portable containers. These containers ensure consistent execution across different environments, eliminating dependency management and configuration drift issues. While Docker runs natively on Linux, deploying it within a VM offers security, compatibility, and resource management advantages for cloud and enterprise environments.

This post covers Docker installation on Ubuntu, configuration fundamentals, and prepares for the MongoDB replica set deployment covered in the next post.

## Why Docker in VMs?

Although Docker runs more efficiently on bare metal Linux, deploying it within a VM provides several benefits:

### Security Isolation

Running Docker in a VM adds an isolation layer that prevents containers from directly interacting with the host system. This mitigates the risk of container escapes and unauthorized access to underlying resources. Multi-tenant environments benefit significantly from this approach, as VMs establish strict boundaries between workloads, ensuring that a compromised container does not affect others.

### Cross-Platform Compatibility

Since Docker relies on Linux kernel features such as namespaces and control groups (cgroups), a Linux VM provides a fully functional environment for containerized workloads regardless of the host OS. This consistency simplifies development and testing by creating a controlled OS environment, eliminating host-specific configuration concerns.

### Resource Management

Virtualization platforms allow precise CPU, memory, and disk resource allocation, preventing containerized applications from consuming excessive host resources. VMs serve as container hosts in cloud computing, ensuring efficient scaling and workload distribution.

### Networking and Kernel Configuration

Containers often require specific network setups or kernel modules that may not be available on a shared host. A VM enables custom kernel tuning without affecting other workloads, making it an ideal solution for specialized deployments.

### Portability and Reproducibility

A preconfigured VM with Docker can migrate across different hypervisors or cloud providers, ensuring a consistent runtime environment. This portability benefits CI/CD pipelines, where disposable, identical environments streamline automated testing and deployment.

## Prerequisites

- Ubuntu 24.04 LTS (or similar) VM or physical machine
- sudo access
- Internet connectivity for downloading packages

## Installing Docker Engine

Follow the official Docker installation process for Ubuntu.

### Remove Conflicting Packages

Remove any existing Docker-related packages:

```bash
sudo apt remove docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc
```

### Add Docker's Official GPG Key

Install prerequisites and add Docker's repository key:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

### Add Docker Repository

Add the Docker repository to apt sources:

```bash
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
```

### Install Docker Packages

Install Docker Engine, CLI, containerd, and plugins:

```bash
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

This installs:
- **docker-ce**: Docker Engine (Community Edition)
- **docker-ce-cli**: Docker command-line interface
- **containerd.io**: Container runtime
- **docker-buildx-plugin**: Multi-platform build support
- **docker-compose-plugin**: Docker Compose V2

### Verify Installation

Check Docker is installed:

```bash
docker --version
```

Output:

```
Docker version 27.4.0, build bde2b89
```

Check Docker Compose:

```bash
docker compose version
```

Output:

```
Docker Compose version v2.30.3
```

## Testing Docker Installation

Run the hello-world container to verify Docker works:

```bash
sudo docker run hello-world
```

Output:

```
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
e6590344b1a5: Pull complete
Digest: sha256:e0b569a5163a5e6be84e210a2587e7d447e08f87a0e90798363fa44a0464a1e8
Status: Downloaded newer image for hello-world:latest

Hello from Docker!
This message shows that your installation appears to be working correctly.

To generate this message, Docker took the following steps:
 1. The Docker client contacted the Docker daemon.
 2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (amd64)
 3. The Docker daemon created a new container from that image which runs the
    executable that produces the output you are currently reading.
 4. The Docker daemon streamed that output to the Docker client, which sent it
    to your terminal.
```

This confirms Docker is working correctly.

## Configuring Docker for Non-Root Access (Optional)

By default, Docker requires sudo. To run Docker commands without sudo, add your user to the docker group:

```bash
sudo usermod -aG docker $USER
```

Log out and log back in for the change to take effect, or run:

```bash
newgrp docker
```

Test without sudo:

```bash
docker run hello-world
```

## Understanding Docker Components

### Docker Daemon (dockerd)

The background service that manages containers, images, networks, and volumes. Runs as a systemd service:

```bash
sudo systemctl status docker
```

### Docker CLI (docker)

The command-line tool for interacting with the Docker daemon. Commands follow the pattern:

```bash
docker <command> <options>
```

Common commands:
- `docker run`: Create and start a container
- `docker ps`: List running containers
- `docker images`: List downloaded images
- `docker build`: Build an image from a Dockerfile
- `docker compose`: Manage multi-container applications

### containerd

The container runtime that executes containers. Docker uses containerd under the hood to manage container lifecycle.

### Docker Compose

Tool for defining and running multi-container applications using YAML configuration files. Simplifies managing related containers (e.g., web app + database).

## Pulling Container Images

Container images are templates for creating containers. Pull the MongoDB image for use in the next post:

```bash
docker pull mongodb/mongodb-community-server:latest
```

Output:

```
latest: Pulling from mongodb/mongodb-community-server
9cb31e2e37ea: Pull complete
80fa1dac73f5: Pull complete
025db36d2934: Pull complete
d17667df96e1: Pull complete
2908e1e1cddd: Pull complete
ea022fe25868: Pull complete
a1d99c33e5c8: Pull complete
42050dbd93f9: Pull complete
f52d14930017: Pull complete
4f4fb700ef54: Pull complete
5c8da43f0543: Pull complete
Digest: sha256:4108be7f8ffdcfbabc59ce978825ab7b98389441a62393bda2ed1f2ccd72ff2a
Status: Downloaded newer image for mongodb/mongodb-community-server:latest
docker.io/mongodb/mongodb-community-server:latest
```

List downloaded images:

```bash
docker images
```

Output:

```
REPOSITORY                          TAG       IMAGE ID       CREATED        SIZE
mongodb/mongodb-community-server    latest    a1b2c3d4e5f6   2 weeks ago    715MB
hello-world                         latest    9c7a54a9a43c   6 months ago   13.3kB
```

## Docker Networking Basics

Docker creates isolated networks for container communication.

### Network Types

- **bridge**: Default network type, containers on same bridge can communicate
- **host**: Container uses host network directly (no isolation)
- **none**: No networking
- **overlay**: Multi-host networking for swarm mode

List networks:

```bash
docker network ls
```

Output:

```
NETWORK ID     NAME      DRIVER    SCOPE
a1b2c3d4e5f6   bridge    bridge    local
123456789abc   host      host      local
fedcba987654   none      null      local
```

Create a custom bridge network:

```bash
docker network create mongo-network
```

Containers on `mongo-network` can communicate using container names as hostnames.

## Docker Volumes for Persistent Storage

Containers are ephemeral—data inside containers is lost when the container is removed. Volumes persist data outside containers.

### Volume Types

- **Named volumes**: Managed by Docker (`docker volume create`)
- **Bind mounts**: Mount a host directory into a container
- **tmpfs mounts**: Temporary in-memory storage

List volumes:

```bash
docker volume ls
```

Create a volume:

```bash
docker volume create mongo-data
```

Inspect a volume:

```bash
docker volume inspect mongo-data
```

Output shows the mount point on the host:

```json
[
    {
        "Name": "mongo-data",
        "Driver": "local",
        "Mountpoint": "/var/lib/docker/volumes/mongo-data/_data",
        "Scope": "local"
    }
]
```

## Dockerfile Fundamentals

A Dockerfile defines how to build a container image. Basic structure:

```dockerfile
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y nginx
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

- `FROM`: Base image
- `RUN`: Execute commands during build
- `EXPOSE`: Document which ports the container listens on
- `CMD`: Default command when container starts

Build an image from a Dockerfile:

```bash
docker build -t myimage:latest .
```

## Docker Compose Fundamentals

Docker Compose uses YAML files to define multi-container applications. Basic structure:

```yaml
version: '3.8'

services:
  web:
    image: nginx:latest
    ports:
      - "8080:80"
    networks:
      - webnet

  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: example
    volumes:
      - db-data:/var/lib/postgresql/data
    networks:
      - webnet

networks:
  webnet:
    driver: bridge

volumes:
  db-data:
```

Commands:
- `docker compose up`: Start services
- `docker compose down`: Stop and remove services
- `docker compose ps`: List running services
- `docker compose logs`: View service logs

## Common Docker Commands

### Container Management

```bash
# Run a container
docker run -d --name mycontainer nginx:latest

# List running containers
docker ps

# List all containers (including stopped)
docker ps -a

# Stop a container
docker stop mycontainer

# Start a stopped container
docker start mycontainer

# Remove a container
docker rm mycontainer

# View container logs
docker logs mycontainer

# Execute command in running container
docker exec -it mycontainer bash
```

### Image Management

```bash
# List images
docker images

# Remove an image
docker rmi nginx:latest

# Tag an image
docker tag myimage:latest myimage:v1.0

# Push to registry
docker push myregistry/myimage:latest
```

### System Cleanup

```bash
# Remove stopped containers
docker container prune

# Remove unused images
docker image prune

# Remove unused volumes
docker volume prune

# Remove all unused resources
docker system prune -a
```

## Common Issues and Troubleshooting

### Docker Daemon Not Running

If `docker ps` returns "Cannot connect to the Docker daemon":

```bash
sudo systemctl start docker
sudo systemctl enable docker
```

### Permission Denied

If you get permission errors:

- Add user to docker group: `sudo usermod -aG docker $USER`
- Log out and back in
- Verify group membership: `groups`

### Disk Space Issues

Docker images and containers consume disk space. Check usage:

```bash
docker system df
```

Clean up:

```bash
docker system prune -a --volumes
```

### Network Connectivity Issues

If containers can't communicate:

- Verify they're on the same network: `docker network inspect <network>`
- Check firewall rules
- Verify DNS resolution inside containers: `docker exec <container> ping <other-container>`

## What's Next

With Docker installed and configured, the environment is ready for container deployments. The next post demonstrates building a MongoDB replica set using Docker Compose, showcasing how Docker simplifies deploying distributed databases with automatic replication and failover.

## Summary

This post covered:

- Why run Docker in VMs (security, compatibility, resource management)
- Installing Docker Engine on Ubuntu
- Adding Docker repository and GPG keys
- Installing Docker packages (engine, CLI, containerd, plugins)
- Testing Docker with hello-world container
- Configuring non-root Docker access
- Docker components (daemon, CLI, containerd, Compose)
- Pulling container images from Docker Hub
- Docker networking basics and custom networks
- Docker volumes for persistent storage
- Dockerfile structure and basics
- Docker Compose YAML fundamentals
- Common Docker commands for containers and images
- System cleanup and resource management
- Troubleshooting daemon, permissions, and disk space issues

Docker is now operational and ready for containerized application deployments. In the next post, we'll build a production-ready MongoDB replica set using Docker Compose, demonstrating high availability and automatic failover.
