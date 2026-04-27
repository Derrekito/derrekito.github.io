---
title: "Ansible Setup and First Playbook: Infrastructure as Code Fundamentals"
date: 2027-01-11
categories: [Cloud Computing, Automation]
tags: [ansible, infrastructure-as-code, automation, devops, configuration-management, yaml]
---

Ansible provides infrastructure automation through declarative configuration management. Instead of manually configuring servers or maintaining outdated documentation, Ansible playbooks define the desired state of systems and automatically enforce it. This approach eliminates configuration drift, improves reproducibility, and creates an auditable record of infrastructure changes.

This post covers Ansible installation, core concepts, and demonstrates creating a first playbook that manages files across multiple servers.

## Why Configuration Management?

Maintaining large fleets of servers presents several challenges:

### Configuration Drift

Over time, servers accumulate unique configurations through manual changes, creating "snowflake" systems that are difficult to reproduce. When these systems fail, recreating them becomes guesswork.

### Knowledge Loss

Traditional approaches store setup knowledge in wikis, notes, or engineer memories. These instructions become outdated as environments change, requiring constant review and updates.

### Technical Debt

Undocumented manual changes accumulate as technical debt. New team members struggle to understand current system states, and troubleshooting becomes increasingly difficult.

### Configuration Management Benefits

Configuration management systems like Ansible solve these problems:

1. **Declarative State**: Define what the system should look like, not how to configure it
2. **Idempotency**: Run playbooks multiple times safely; only necessary changes are applied
3. **Version Control**: Store configurations in Git for review, rollback, and auditing
4. **Documentation as Code**: Configuration files serve as living documentation
5. **Reproducibility**: Recreate identical systems from code
6. **Testing**: Validate configurations before deploying to production

## What is Ansible?

Ansible is an agentless automation framework that:

- Uses SSH to connect to managed nodes (no agent installation required)
- Provides prebuilt modules for common tasks (package installation, file management, service control)
- Supports idempotent operations (applying the same playbook multiple times is safe)
- Uses YAML for human-readable configuration
- Extends via Ansible Galaxy (community module repository)

### Ansible vs. Other Tools

| Feature | Ansible | Puppet | Chef | SaltStack |
|---------|---------|--------|------|-----------|
| Agent | No | Yes | Yes | Yes |
| Language | YAML | Ruby DSL | Ruby | YAML/Python |
| Push/Pull | Push | Pull | Pull | Both |
| Learning Curve | Low | Medium | High | Medium |

Ansible's agentless architecture and YAML-based playbooks make it accessible for beginners while remaining powerful for complex automation.

## Installing Ansible

### On Ubuntu (Control Node)

Install Ansible on your workstation or control node:

```bash
sudo apt-get update
sudo apt-get install -y ansible
```

Output:

```
Reading package lists... Done
Building dependency tree... Done
The following additional packages will be installed:
  ansible-core python3-argcomplete python3-dnspython python3-kerberos
  python3-libcloud python3-lockfile python3-ntlm-auth python3-passlib
  python3-requests-ntlm python3-resolvelib python3-selinux
  python3-simplejson python3-winrm python3-xmltodict
The following NEW packages will be installed:
  ansible ansible-core [...]
0 upgraded, 15 newly installed, 0 to remove and 4 not upgraded.
Need to get 19.5 MB of archives.
After this operation, 315 MB of additional disk space will be used.
```

### Verify Installation

Check Ansible version:

```bash
ansible-playbook --version
```

Output:

```
ansible-playbook [core 2.16.3]
  config file = None
  configured module search path = ['/home/user/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /usr/lib/python3/dist-packages/ansible
  ansible collection location = /home/user/.ansible/collections:/usr/share/ansible/collections
  executable location = /usr/bin/ansible-playbook
  python version = 3.12.3 (main, Feb  4 2025, 14:48:35) [GCC 13.3.0] (/usr/bin/python3)
  jinja version = 3.1.2
  libyaml = True
```

Ansible 2.16+ with Python 3.12 is ready for automation.

## Ansible Architecture

### Components

- **Control Node**: Machine where Ansible is installed and playbooks are executed
- **Managed Nodes**: Servers managed by Ansible (requires Python and SSH)
- **Inventory**: List of managed nodes and their groupings
- **Playbook**: YAML file defining tasks to execute
- **Module**: Reusable unit of work (e.g., `apt`, `copy`, `service`)
- **Role**: Organized collection of tasks, variables, and templates
- **Handler**: Task triggered by changes (e.g., restart service after config change)

### How Ansible Works

1. Read playbook and inventory
2. Connect to managed nodes via SSH
3. Copy and execute modules on managed nodes
4. Collect results and report status
5. Clean up temporary files

All communication happens over SSH; managed nodes don't need Ansible installed.

## Setting Up SSH Access

Ansible requires passwordless SSH to managed nodes. Generate an SSH key:

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/ansible_key
```

Copy the public key to managed nodes:

```bash
ssh-copy-id -i ~/.ssh/ansible_key.pub ubuntu@managed-node1
ssh-copy-id -i ~/.ssh/ansible_key.pub ubuntu@managed-node2
```

Test SSH access:

```bash
ssh -i ~/.ssh/ansible_key ubuntu@managed-node1
```

If the connection succeeds without a password prompt, SSH is configured correctly.

## Creating an Inventory

The inventory defines which hosts Ansible manages. Create a directory structure:

```bash
mkdir ansible-demo
cd ansible-demo
mkdir inventory
```

Create `inventory/hosts.yml`:

```yaml
ungrouped:
  hosts:
    primary1:
    secondary1:
    secondary2:

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
```

**Explanation**:
- **ungrouped**: All hosts listed individually
- **primary**: Group containing primary servers
- **secondary**: Group containing secondary servers
- **all**: Special group containing all hosts, with shared variables
  - `ansible_user`: SSH username
  - `ansible_ssh_private_key_file`: Path to SSH private key

Groups enable targeting specific server types (e.g., run tasks only on secondaries).

## Ansible Configuration (Optional)

Create `ansible.cfg` in the project directory:

```ini
[defaults]
inventory = inventory/hosts.yml
host_key_checking = False
retry_files_enabled = False
```

This sets the default inventory and disables SSH host key checking (useful for dynamic environments).

## First Playbook: Creating a File

Create `team_file.yml`:

```yaml
---
- name: Create team file on all hosts
  hosts: all

  tasks:
    - name: Put team names in /root/team.txt
      ansible.builtin.copy:
        dest: /root/team.txt
        owner: ubuntu
        group: ubuntu
        mode: '0644'
        content: |
          Alice "The Architect" Anderson
          Bob "The Builder" Brown
          Carol "The Coder" Chen
      become: yes
```

**Breakdown**:
- `---`: YAML document start
- `name`: Human-readable description of the play
- `hosts: all`: Target all hosts in the inventory
- `tasks`: List of tasks to execute
- `ansible.builtin.copy`: Built-in module to create/copy files
  - `dest`: Target file path
  - `owner`/`group`: File ownership
  - `mode`: File permissions (octal)
  - `content`: Inline file content (multiline with `|`)
- `become: yes`: Execute with sudo privileges

## Running the Playbook

Execute the playbook:

```bash
ansible-playbook -i inventory/hosts.yml team_file.yml
```

Output:

```
PLAY [Create team file on all hosts] ****************************************

TASK [Gathering Facts] ******************************************************
ok: [primary1]
ok: [secondary1]
ok: [secondary2]

TASK [Put team names in /root/team.txt] *************************************
changed: [primary1]
changed: [secondary1]
changed: [secondary2]

PLAY RECAP ******************************************************************
primary1      : ok=2    changed=1    unreachable=0    failed=0    skipped=0
secondary1    : ok=2    changed=1    unreachable=0    failed=0    skipped=0
secondary2    : ok=2    changed=1    unreachable=0    failed=0    skipped=0
```

**Status Meanings**:
- **ok**: Task completed successfully, no changes needed
- **changed**: Task completed and made changes
- **unreachable**: Host couldn't be contacted
- **failed**: Task failed
- **skipped**: Task was skipped based on conditions

The file was created on all three hosts.

## Verifying the Result

SSH to a managed node and check the file:

```bash
ssh ubuntu@primary1
cat /root/team.txt
```

Output:

```
Alice "The Architect" Anderson
Bob "The Builder" Brown
Carol "The Coder" Chen
```

## Testing Idempotency

Run the playbook again:

```bash
ansible-playbook -i inventory/hosts.yml team_file.yml
```

Output:

```
PLAY [Create team file on all hosts] ****************************************

TASK [Gathering Facts] ******************************************************
ok: [primary1]
ok: [secondary1]
ok: [secondary2]

TASK [Put team names in /root/team.txt] *************************************
ok: [primary1]
ok: [secondary2]
ok: [secondary1]

PLAY RECAP ******************************************************************
primary1      : ok=2    changed=0    unreachable=0    failed=0    skipped=0
secondary1    : ok=2    changed=0    unreachable=0    failed=0    skipped=0
secondary2    : ok=2    changed=0    unreachable=0    failed=0    skipped=0
```

Notice `changed=0` for all hosts. Ansible detected the file already exists with the correct content and skipped making changes. **This is idempotency in action.**

## Targeting Specific Hosts

Run the playbook only on primary hosts:

```bash
ansible-playbook -i inventory/hosts.yml -l primary team_file.yml
```

The `-l` (limit) flag restricts execution to the `primary` group.

Output:

```
PLAY RECAP ******************************************************************
primary1      : ok=2    changed=0    unreachable=0    failed=0    skipped=0
```

Only `primary1` was targeted.

## Common Ansible Modules

### Package Management

Install packages:

```yaml
- name: Install nginx
  ansible.builtin.apt:
    name: nginx
    state: present
  become: yes
```

### Service Management

Ensure a service is running:

```yaml
- name: Start nginx
  ansible.builtin.service:
    name: nginx
    state: started
    enabled: yes
  become: yes
```

### File Management

Create a directory:

```yaml
- name: Create data directory
  ansible.builtin.file:
    path: /data
    state: directory
    owner: ubuntu
    mode: '0755'
  become: yes
```

### Command Execution

Run arbitrary commands:

```yaml
- name: Check disk usage
  ansible.builtin.command: df -h
  register: disk_usage

- name: Display disk usage
  ansible.builtin.debug:
    var: disk_usage.stdout_lines
```

## Dry Run (Check Mode)

Test what would change without applying:

```bash
ansible-playbook -i inventory/hosts.yml team_file.yml --check
```

Output shows what would change without actually making changes.

## Common Issues and Troubleshooting

### SSH Connection Failures

If Ansible can't connect:

1. **Verify SSH access**:
   ```bash
   ssh -i ~/.ssh/ansible_key ubuntu@primary1
   ```

2. **Check inventory hostname resolution**:
   ```bash
   ping primary1
   ```

3. **Increase verbosity**:
   ```bash
   ansible-playbook -vvv team_file.yml
   ```

### Permission Denied Errors

If tasks fail with permission errors:

- Add `become: yes` to tasks requiring root
- Verify the user has sudo permissions: `sudo -l`
- Configure passwordless sudo: `echo "ubuntu ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ubuntu`

### Python Not Found

If Ansible reports "Python not found":

- Install Python on managed nodes: `sudo apt install python3`
- Specify Python interpreter in inventory:
  ```yaml
  all:
    vars:
      ansible_python_interpreter: /usr/bin/python3
  ```

### YAML Syntax Errors

YAML is whitespace-sensitive. Validate syntax:

```bash
ansible-playbook --syntax-check team_file.yml
```

## What's Next

With Ansible fundamentals in place, the next post demonstrates automating MongoDB cluster deployment using roles, templates, and handlers. This builds on the Docker and manual configuration from previous posts, showing how Ansible eliminates repetitive manual work.

## Summary

This post covered:

- Why configuration management matters (drift, knowledge loss, technical debt)
- Configuration management benefits (idempotency, version control, reproducibility)
- Ansible architecture (control node, managed nodes, agentless)
- Installing Ansible on Ubuntu
- Setting up SSH key authentication
- Creating an inventory file with host groups
- Writing a first playbook with the copy module
- Running playbooks and interpreting output
- Verifying idempotency by running playbooks multiple times
- Targeting specific host groups with the -l flag
- Common Ansible modules (apt, service, file, command)
- Testing playbooks with check mode
- Troubleshooting SSH, permissions, Python, and YAML errors

Ansible is now configured and ready for infrastructure automation. In the next post, we'll automate MongoDB cluster deployment, demonstrating how Ansible manages complex multi-node configurations.
