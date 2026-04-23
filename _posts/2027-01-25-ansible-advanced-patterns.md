---
title: "Advanced Ansible Patterns: Idempotency, Error Handling, and Automation"
date: 2027-01-25
categories: [Cloud Computing, Automation]
tags: [ansible, automation, devops, idempotency, error-handling, monitoring, inotify, systemd]
---

Ansible's power extends beyond basic automation. Advanced patterns like idempotency enforcement, sophisticated error handling, automated configuration monitoring, and integration with system services make infrastructure truly self-maintaining. This post covers best practices and advanced techniques for production-ready Ansible automation.

This final post in the series demonstrates patterns that separate basic automation from robust, production-grade infrastructure management.

## Idempotency Best Practices

Idempotency means running a playbook multiple times produces the same result as running it once. This is critical for safe automation.

### Why Idempotency Matters

- **Safe Re-runs**: Apply playbooks without fear of breaking working systems
- **Drift Detection**: Re-running playbooks reveals configuration drift
- **Recovery**: Restore systems to desired state after failures
- **Continuous Enforcement**: Periodically apply playbooks to maintain compliance

### Ensuring Idempotent Tasks

**Bad (Not Idempotent)**:

```yaml
- name: Add user to group
  ansible.builtin.shell: usermod -aG docker ubuntu
```

This runs every time, even if the user is already in the group.

**Good (Idempotent)**:

```yaml
- name: Add user to group
  ansible.builtin.user:
    name: ubuntu
    groups: docker
    append: yes
```

Ansible checks current state and only makes changes if needed.

### Using `changed_when` and `failed_when`

Control when tasks report changes or failures:

```yaml
- name: Check if MongoDB is initialized
  ansible.builtin.shell: docker exec mongo-primary mongosh --eval "rs.status()"
  register: rs_status
  changed_when: false  # Never report as changed
  failed_when: rs_status.rc != 0 and 'not yet initialized' not in rs_status.stderr

- name: Initialize replica set
  ansible.builtin.shell: |
    docker exec mongo-primary mongosh --eval '
      rs.initiate({
        _id: "rs0",
        members: [
          { _id: 0, host: "primary1:27017" },
          { _id: 1, host: "secondary1:27017" },
          { _id: 2, host: "secondary2:27017" }
        ]
      })'
  when: "'not yet initialized' in rs_status.stderr"
```

This initializes the replica set only if it's not already initialized.

### Check Mode (Dry Run)

Always test playbooks with check mode:

```bash
ansible-playbook mongo_install.yml --check
```

This shows what would change without making changes.

### Diff Mode

Show exact changes before applying:

```bash
ansible-playbook mongo_install.yml --check --diff
```

This displays file diffs for configuration changes.

## Error Handling and Recovery

Production automation must handle failures gracefully.

### Block/Rescue/Always

Handle errors and ensure cleanup:

```yaml
- name: Deploy application
  block:
    - name: Stop existing container
      community.docker.docker_container:
        name: myapp
        state: stopped

    - name: Deploy new container
      community.docker.docker_container:
        name: myapp
        image: myapp:latest
        state: started

  rescue:
    - name: Rollback to previous version
      community.docker.docker_container:
        name: myapp
        image: myapp:previous
        state: started

    - name: Send failure notification
      ansible.builtin.debug:
        msg: "Deployment failed, rolled back to previous version"

  always:
    - name: Clean up temporary files
      ansible.builtin.file:
        path: /tmp/deploy
        state: absent
```

**Execution Flow**:
- **block**: Tasks execute normally
- **rescue**: Executes only if block fails
- **always**: Always executes (cleanup)

### Ignoring Errors

Continue execution even if a task fails:

```yaml
- name: Try to stop container (may not exist)
  community.docker.docker_container:
    name: old-container
    state: stopped
  ignore_errors: yes
```

Use sparingly; usually better to check state first.

### Retry Logic

Retry tasks that may fail temporarily:

```yaml
- name: Pull Docker image
  community.docker.docker_image:
    name: mongodb/mongodb-community-server:latest
    source: pull
  register: pull_result
  retries: 3
  delay: 10
  until: pull_result is succeeded
```

Retries up to 3 times with 10-second delays.

### Assertions

Validate conditions before proceeding:

```yaml
- name: Check disk space
  ansible.builtin.shell: df -h / | tail -1 | awk '{print $5}' | sed 's/%//'
  register: disk_usage

- name: Ensure sufficient disk space
  ansible.builtin.assert:
    that:
      - disk_usage.stdout | int < 80
    fail_msg: "Disk usage is {{ disk_usage.stdout }}%, requires < 80%"
    success_msg: "Disk usage {{ disk_usage.stdout }}% is acceptable"
```

Playbook fails if disk usage exceeds 80%.

## Dynamic Inventories

For cloud environments, generate inventories dynamically.

### AWS EC2 Dynamic Inventory

Install the AWS collection:

```bash
ansible-galaxy collection install amazon.aws
```

Create `inventory/aws_ec2.yml`:

```yaml
plugin: amazon.aws.aws_ec2
regions:
  - us-east-1
keyed_groups:
  - key: tags.Role
    prefix: role
  - key: tags.Environment
    prefix: env
```

Use it:

```bash
ansible-playbook -i inventory/aws_ec2.yml playbook.yml
```

Ansible queries AWS API for current instances.

### Script-Based Dynamic Inventory

Create a script that outputs JSON:

```python
#!/usr/bin/env python3
import json

inventory = {
    "primary": {
        "hosts": ["primary1"],
        "vars": {"mongodb_role": "primary"}
    },
    "secondary": {
        "hosts": ["secondary1", "secondary2"],
        "vars": {"mongodb_role": "secondary"}
    },
    "_meta": {
        "hostvars": {
            "primary1": {"ansible_host": "192.168.56.110"},
            "secondary1": {"ansible_host": "192.168.56.111"},
            "secondary2": {"ansible_host": "192.168.56.112"}
        }
    }
}

print(json.dumps(inventory))
```

Make it executable and use it:

```bash
chmod +x inventory.py
ansible-playbook -i inventory.py playbook.yml
```

## Automated Configuration Monitoring

Automatically re-apply configurations when files change using inotify and systemd.

### Installing inotify-tools

```bash
sudo apt install inotify-tools ansible
```

### Creating the Monitoring Script

Create `/usr/local/bin/ansible-watch.sh`:

```bash
#!/bin/bash

# Directory to monitor
WATCH_DIR="/opt/mongo-cluster-playbook"

# Command to run (Ansible playbook)
COMMAND_TO_RUN="ansible-playbook /opt/mongo-cluster-playbook/mongo_install.yml -i /opt/mongo-cluster-playbook/inventory/hosts.yml"

# Log file
LOG_FILE="/var/log/ansible-watch.log"

echo "$(date): Starting Ansible configuration watcher" >> "$LOG_FILE"

# Monitor the directory for changes
inotifywait -m "$WATCH_DIR" -e create -e modify -e delete |
    while read -r path action file; do
        echo "$(date): Change detected: $file ($action) in $path" >> "$LOG_FILE"
        
        # Use lock file to prevent concurrent runs
        if [ ! -f /tmp/ansible-watch.lock ]; then
            touch /tmp/ansible-watch.lock
            
            echo "$(date): Executing Ansible playbook" >> "$LOG_FILE"
            eval "$COMMAND_TO_RUN" >> "$LOG_FILE" 2>&1
            
            # Wait 5 seconds to avoid rapid triggers
            sleep 5
            rm -f /tmp/ansible-watch.lock
            
            echo "$(date): Playbook execution completed" >> "$LOG_FILE"
        else
            echo "$(date): Skipping execution, lock file exists" >> "$LOG_FILE"
        fi
    done
```

Make it executable:

```bash
sudo chmod +x /usr/local/bin/ansible-watch.sh
```

### Creating the Systemd Service

Create `/etc/systemd/system/ansible-watch.service`:

```ini
[Unit]
Description=Ansible Configuration Change Monitor
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ansible-watch.sh
Restart=always
RestartSec=10
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### Enabling the Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable ansible-watch.service
sudo systemctl start ansible-watch.service
```

Verify it's running:

```bash
sudo systemctl status ansible-watch.service
```

Now, any change to playbooks in `/opt/mongo-cluster-playbook` triggers automatic re-application. The lock file prevents concurrent runs, and the 5-second cooldown prevents rapid re-executions.

### Monitoring the Watcher

View logs:

```bash
sudo tail -f /var/log/ansible-watch.log
```

Or via journalctl:

```bash
sudo journalctl -u ansible-watch.service -f
```

## Ansible Vault for Secrets

Never store passwords in plain text.

### Creating an Encrypted File

```bash
ansible-vault create secrets.yml
```

Enter a vault password, then add secrets:

```yaml
---
mongodb_admin_password: "SuperSecretPassword123"
database_backup_key: "AnotherSecret456"
```

### Editing Encrypted Files

```bash
ansible-vault edit secrets.yml
```

### Using Encrypted Variables

Reference vault variables in playbooks:

```yaml
- name: Set MongoDB admin password
  ansible.builtin.shell: |
    docker exec mongo-primary mongosh --eval '
      db.getSiblingDB("admin").createUser({
        user: "admin",
        pwd: "{{ mongodb_admin_password }}",
        roles: ["root"]
      })'
  vars_files:
    - secrets.yml
```

### Running with Vault

```bash
ansible-playbook mongo_install.yml --ask-vault-pass
```

Or use a password file:

```bash
echo "MyVaultPassword" > .vault_pass
chmod 600 .vault_pass
ansible-playbook mongo_install.yml --vault-password-file .vault_pass
```

## Tags for Selective Execution

Run specific parts of playbooks:

```yaml
- name: Install packages
  ansible.builtin.apt:
    name: docker-ce
    state: present
  tags:
    - install
    - docker

- name: Configure firewall
  ansible.builtin.ufw:
    rule: allow
    port: 27017
  tags:
    - configure
    - security
```

Run only tagged tasks:

```bash
ansible-playbook mongo_install.yml --tags install
ansible-playbook mongo_install.yml --tags security
```

Skip tagged tasks:

```bash
ansible-playbook mongo_install.yml --skip-tags security
```

## Ansible Best Practices Summary

### Organization

1. **Use roles** for reusable components
2. **Group variables** by host groups
3. **Use version control** (Git) for all playbooks
4. **Document with comments** in complex tasks

### Safety

1. **Test with --check** before applying
2. **Use --diff** to see changes
3. **Implement error handling** (block/rescue)
4. **Validate with assertions** before risky operations

### Maintainability

1. **Keep tasks idempotent** (use built-in modules)
2. **Use meaningful names** for tasks and variables
3. **Avoid shell/command** modules when alternatives exist
4. **Separate secrets** with Ansible Vault

### Performance

1. **Use async** for long-running tasks
2. **Minimize gather_facts** if not needed
3. **Use pipelining** for SSH optimization
4. **Batch operations** when possible

## Troubleshooting Complex Playbooks

### Increased Verbosity

```bash
ansible-playbook playbook.yml -v    # Verbose
ansible-playbook playbook.yml -vv   # More verbose
ansible-playbook playbook.yml -vvv  # Very verbose
ansible-playbook playbook.yml -vvvv # Debug level
```

### Step-by-Step Execution

Run one task at a time, prompting before each:

```bash
ansible-playbook playbook.yml --step
```

### Start at Specific Task

Resume from a specific task:

```bash
ansible-playbook playbook.yml --start-at-task="Deploy MongoDB container"
```

### Debugging Variables

Print variables for troubleshooting:

```yaml
- name: Debug variables
  ansible.builtin.debug:
    msg: |
      Hostname: {{ inventory_hostname }}
      MongoDB role: {{ mongodb_role }}
      Container name: {{ container_name }}
```

## Series Conclusion

This 16-part series covered cloud computing from foundations to automation:

**OpenStack (Parts 1-10)**: Built a complete private cloud with identity, compute, networking, storage, and web management.

**Docker (Parts 11-13)**: Containerized applications with replica sets and health monitoring.

**Ansible (Parts 14-16)**: Automated infrastructure deployment and configuration management.

Together, these technologies enable:
- **Infrastructure as Code**: Define infrastructure in version-controlled files
- **Reproducibility**: Recreate environments consistently
- **Automation**: Eliminate manual configuration
- **Self-Healing**: Automatically enforce desired state
- **Scalability**: Deploy to dozens or thousands of nodes

The skills from this series apply to cloud platforms (AWS, Azure, GCP), container orchestrators (Kubernetes), and modern DevOps practices.

## What's Next

Continue your cloud computing journey:

1. **Kubernetes**: Container orchestration at scale
2. **Terraform**: Multi-cloud infrastructure provisioning
3. **CI/CD**: Jenkins, GitLab CI, GitHub Actions
4. **Monitoring**: Prometheus, Grafana, ELK stack
5. **Service Mesh**: Istio, Linkerd for microservices

## Summary

This post covered:

- Idempotency best practices and enforcement
- Using changed_when and failed_when for control
- Check mode and diff mode for safe testing
- Error handling with block/rescue/always
- Retry logic for transient failures
- Assertions for validation
- Dynamic inventories for cloud environments
- Automated configuration monitoring with inotify
- Creating systemd services for automation daemons
- Ansible Vault for secret management
- Tags for selective playbook execution
- Best practices for organization, safety, and maintainability
- Troubleshooting with verbosity, step mode, and debugging
- Series recap and next steps

The cloud computing series is complete! You now have the knowledge to build, deploy, and automate cloud infrastructure from OpenStack foundations through container orchestration to configuration management.
