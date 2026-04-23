---
title: "Automating MongoDB Clusters with Ansible: Roles and Templates"
date: 2027-01-18
categories: [Cloud Computing, Automation]
tags: [ansible, mongodb, automation, roles, templates, configuration-management, docker]
---

Ansible excels at automating complex deployments like MongoDB clusters. Instead of manually configuring each server, Ansible playbooks define the cluster state and automatically deploy it across multiple nodes. This post demonstrates automating MongoDB cluster deployment using Ansible roles, templates, and the Docker containers from previous posts.

This builds on the Ansible fundamentals from the previous post, showing how to organize complex automation with roles and manage configuration files with Jinja2 templates.

## Project Overview

This automation deploys a MongoDB cluster across three nodes:
- **primary1**: Primary MongoDB node
- **secondary1**: Secondary MongoDB node
- **secondary2**: Secondary MongoDB node

Each node runs MongoDB in a Docker container, configured via Ansible with:
- Docker installation and configuration
- MongoDB container deployment
- Node-specific configurations using templates
- Automated initialization of the replica set

## Project Structure

Create a well-organized project directory:

```bash
mkdir -p mongo-cluster-playbook/{inventory,roles/{common,primary,secondary}/{tasks,handlers,templates},group_vars}
cd mongo-cluster-playbook
```

Final structure:

```
mongo-cluster-playbook/
├── inventory/
│   └── hosts.yml
├── group_vars/
│   ├── all.yml
│   ├── primary.yml
│   └── secondary.yml
├── roles/
│   ├── common/
│   │   └── tasks/
│   │       └── main.yml
│   ├── primary/
│   │   ├── tasks/
│   │   │   └── main.yml
│   │   ├── handlers/
│   │   │   └── main.yml
│   │   └── templates/
│   │       └── mongod.conf.j2
│   └── secondary/
│       ├── tasks/
│       │   └── main.yml
│       ├── handlers/
│       │   └── main.yml
│       └── templates/
│           └── mongod.conf.j2
├── docker_install.yml
└── mongo_install.yml
```

## Understanding Ansible Roles

Roles organize playbooks into reusable components:

- **tasks/**: Actions to perform (main.yml is the entry point)
- **handlers/**: Tasks triggered by changes (e.g., restart services)
- **templates/**: Jinja2 templates for configuration files
- **vars/**: Role-specific variables
- **files/**: Static files to copy
- **defaults/**: Default variables (lowest precedence)

Roles promote reusability and organization, making complex playbooks maintainable.

## Setting Up the Inventory

Create `inventory/hosts.yml`:

```yaml
ungrouped:
  hosts:
    primary1:
      ansible_host: 192.168.56.110
    secondary1:
      ansible_host: 192.168.56.111
    secondary2:
      ansible_host: 192.168.56.112

primary:
  hosts:
    primary1:

secondary:
  hosts:
    secondary1:
    secondary2:

all:
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ~/.ssh/ansible_key
    ansible_become: yes
```

Replace IP addresses with your actual managed node IPs.

## Defining Group Variables

Variables can be scoped to specific host groups.

### All Hosts (`group_vars/all.yml`)

```yaml
---
mongodb_version: "latest"
replica_set_name: "rs0"
mongodb_port: 27017
```

### Primary Hosts (`group_vars/primary.yml`)

```yaml
---
mongodb_role: "primary"
container_name: "mongo-primary"
```

### Secondary Hosts (`group_vars/secondary.yml`)

```yaml
---
mongodb_role: "secondary"
container_name: "mongo-secondary"
```

These variables are accessible in roles and templates.

## Installing Docker

Create `docker_install.yml`:

```yaml
---
- name: Install Docker on all hosts
  hosts: all

  tasks:
    - name: Add Docker GPG apt key
      ansible.builtin.apt_key:
        url: https://download.docker.com/linux/ubuntu/gpg
        state: present

    - name: Add Docker repository
      ansible.builtin.apt_repository:
        repo: deb https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable
        state: present

    - name: Update apt cache and install docker-ce
      ansible.builtin.apt:
        name: docker-ce
        state: latest
        update_cache: yes

    - name: Install Docker Python module
      ansible.builtin.apt:
        name: python3-docker
        state: latest

    - name: Add ubuntu user to docker group
      ansible.builtin.user:
        name: ubuntu
        groups: docker
        append: yes
```

Run the playbook:

```bash
ansible-playbook -i inventory/hosts.yml docker_install.yml
```

Output:

```
PLAY [Install Docker on all hosts] ******************************************

TASK [Gathering Facts] ******************************************************
ok: [secondary1]
ok: [secondary2]
ok: [primary1]

TASK [Add Docker GPG apt key] ***********************************************
changed: [primary1]
changed: [secondary2]
changed: [secondary1]

TASK [Add Docker repository] ************************************************
changed: [primary1]
changed: [secondary1]
changed: [secondary2]

TASK [Update apt cache and install docker-ce] ******************************
changed: [primary1]
changed: [secondary2]
changed: [secondary1]

TASK [Install Docker Python module] *****************************************
changed: [primary1]
changed: [secondary2]
changed: [secondary1]

TASK [Add ubuntu user to docker group] **************************************
changed: [secondary2]
changed: [secondary1]
changed: [primary1]

PLAY RECAP ******************************************************************
primary1      : ok=6    changed=5    unreachable=0    failed=0    skipped=0
secondary1    : ok=6    changed=5    unreachable=0    failed=0    skipped=0
secondary2    : ok=6    changed=5    unreachable=0    failed=0    skipped=0
```

Docker is now installed on all nodes.

## Creating the Common Role

The common role performs setup tasks shared by all nodes.

Create `roles/common/tasks/main.yml`:

```yaml
---
- name: Update apt cache
  ansible.builtin.apt:
    update_cache: yes
    cache_valid_time: 3600

- name: Install required packages
  ansible.builtin.apt:
    name:
      - python3-pip
      - curl
    state: present

- name: Pull MongoDB Docker image
  community.docker.docker_image:
    name: "mongodb/mongodb-community-server:{{ mongodb_version }}"
    source: pull
```

This role ensures dependencies are installed and the MongoDB image is pulled.

## Creating the Primary Role

The primary role deploys the primary MongoDB node.

### Primary Tasks (`roles/primary/tasks/main.yml`)

```yaml
---
- name: Create MongoDB data directory
  ansible.builtin.file:
    path: /data/mongodb
    state: directory
    owner: "999"  # MongoDB user in container
    group: "999"
    mode: '0755'

- name: Deploy MongoDB container on primary
  community.docker.docker_container:
    name: "{{ container_name }}"
    image: "mongodb/mongodb-community-server:{{ mongodb_version }}"
    state: started
    restart_policy: always
    ports:
      - "{{ mongodb_port }}:27017"
    volumes:
      - /data/mongodb:/data/db
    command: ["mongod", "--replSet", "{{ replica_set_name }}", "--bind_ip_all"]
  notify: Wait for MongoDB to start
```

### Primary Handlers (`roles/primary/handlers/main.yml`)

Handlers execute when notified by tasks:

```yaml
---
- name: Wait for MongoDB to start
  ansible.builtin.wait_for:
    port: "{{ mongodb_port }}"
    delay: 5
    timeout: 60
```

This waits for MongoDB to accept connections before continuing.

## Creating the Secondary Role

The secondary role is similar to the primary but for secondary nodes.

### Secondary Tasks (`roles/secondary/tasks/main.yml`)

```yaml
---
- name: Create MongoDB data directory
  ansible.builtin.file:
    path: /data/mongodb
    state: directory
    owner: "999"
    group: "999"
    mode: '0755'

- name: Deploy MongoDB container on secondary
  community.docker.docker_container:
    name: "{{ container_name }}"
    image: "mongodb/mongodb-community-server:{{ mongodb_version }}"
    state: started
    restart_policy: always
    ports:
      - "{{ mongodb_port }}:27017"
    volumes:
      - /data/mongodb:/data/db
    command: ["mongod", "--replSet", "{{ replica_set_name }}", "--bind_ip_all"]
  notify: Wait for MongoDB to start
```

### Secondary Handlers (`roles/secondary/handlers/main.yml`)

```yaml
---
- name: Wait for MongoDB to start
  ansible.builtin.wait_for:
    port: "{{ mongodb_port }}"
    delay: 5
    timeout: 60
```

## Main Playbook

Create `mongo_install.yml`:

```yaml
---
- name: Deploy MongoDB cluster
  hosts: all
  roles:
    - common

- name: Configure primary MongoDB node
  hosts: primary
  roles:
    - primary

- name: Configure secondary MongoDB nodes
  hosts: secondary
  roles:
    - secondary
```

This playbook applies roles to appropriate host groups.

## Running the Playbook

Execute the full deployment:

```bash
ansible-playbook -i inventory/hosts.yml mongo_install.yml
```

Output:

```
PLAY [Deploy MongoDB cluster] ***********************************************

TASK [Gathering Facts] ******************************************************
ok: [primary1]
ok: [secondary1]
ok: [secondary2]

TASK [common : Update apt cache] ********************************************
ok: [primary1]
ok: [secondary1]
ok: [secondary2]

TASK [common : Install required packages] ***********************************
ok: [primary1]
ok: [secondary1]
ok: [secondary2]

TASK [common : Pull MongoDB Docker image] ***********************************
changed: [primary1]
changed: [secondary1]
changed: [secondary2]

PLAY [Configure primary MongoDB node] ***************************************

TASK [Gathering Facts] ******************************************************
ok: [primary1]

TASK [primary : Create MongoDB data directory] ******************************
changed: [primary1]

TASK [primary : Deploy MongoDB container on primary] ************************
changed: [primary1]

RUNNING HANDLER [primary : Wait for MongoDB to start] ***********************
ok: [primary1]

PLAY [Configure secondary MongoDB nodes] ************************************

TASK [Gathering Facts] ******************************************************
ok: [secondary1]
ok: [secondary2]

TASK [secondary : Create MongoDB data directory] ****************************
changed: [secondary1]
changed: [secondary2]

TASK [secondary : Deploy MongoDB container on secondary] ********************
changed: [secondary1]
changed: [secondary2]

RUNNING HANDLER [secondary : Wait for MongoDB to start] *********************
ok: [secondary1]
ok: [secondary2]

PLAY RECAP ******************************************************************
primary1      : ok=8    changed=3    unreachable=0    failed=0    skipped=0
secondary1    : ok=7    changed=3    unreachable=0    failed=0    skipped=0
secondary2    : ok=7    changed=3    unreachable=0    failed=0    skipped=0
```

MongoDB containers are now running on all three nodes.

## Verifying the Deployment

Check containers are running:

```bash
ansible all -i inventory/hosts.yml -m shell -a "docker ps"
```

Output shows MongoDB containers on all nodes.

## Initializing the Replica Set

The replica set still needs manual initialization (or add a task to automate it):

```bash
ssh ubuntu@primary1
docker exec -it mongo-primary mongosh
```

In the MongoDB shell:

```javascript
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "192.168.56.110:27017" },
    { _id: 1, host: "192.168.56.111:27017" },
    { _id: 2, host: "192.168.56.112:27017" }
  ]
});
```

The replica set is now initialized.

## Using Jinja2 Templates (Advanced)

For more complex configurations, use templates instead of inline commands.

Create `roles/primary/templates/mongod.conf.j2`:

```jinja
# MongoDB configuration for {{ inventory_hostname }}
net:
  port: {{ mongodb_port }}
  bindIp: 0.0.0.0

replication:
  replSetName: {{ replica_set_name }}

storage:
  dbPath: /data/db
```

Use the template in tasks:

```yaml
- name: Deploy MongoDB configuration
  ansible.builtin.template:
    src: mongod.conf.j2
    dest: /etc/mongod.conf
    owner: root
    mode: '0644'
  notify: Restart MongoDB
```

Templates allow dynamic configuration based on variables.

## Common Issues and Troubleshooting

### Docker Module Not Found

If Ansible reports "docker module not found":

- Install the Docker collection:
  ```bash
  ansible-galaxy collection install community.docker
  ```

- Verify it's installed:
  ```bash
  ansible-galaxy collection list | grep docker
  ```

### Containers Don't Start

If containers fail to start:

- Check Docker is running:
  ```bash
  ansible all -i inventory/hosts.yml -m service -a "name=docker state=started"
  ```

- View container logs:
  ```bash
  ansible all -i inventory/hosts.yml -m shell -a "docker logs mongo-primary"
  ```

### Handlers Don't Execute

Handlers only run if notified by a task that reports "changed":

- Verify the task actually made changes
- Check handler name matches the notify name exactly
- Use `--force-handlers` to run handlers even if play fails

## What's Next

With MongoDB cluster deployment automated, the next post covers advanced Ansible patterns including idempotency best practices, error handling, and automated configuration monitoring using inotify and systemd.

## Summary

This post covered:

- Project structure for complex Ansible deployments
- Organizing automation with roles (tasks, handlers, templates)
- Setting up inventory with host groups
- Defining group variables for different node types
- Automating Docker installation across all nodes
- Creating a common role for shared tasks
- Creating primary and secondary roles for MongoDB deployment
- Using handlers to wait for services
- Writing the main playbook to orchestrate role execution
- Running the full MongoDB cluster deployment
- Verifying deployment with ad-hoc commands
- Initializing the replica set
- Using Jinja2 templates for configuration files
- Troubleshooting Docker modules, container failures, and handlers

MongoDB cluster deployment is now fully automated with Ansible. In the final post, we'll cover advanced patterns for maintaining and monitoring infrastructure automation.
