---
title: "Docker Health Checks and Monitoring for MongoDB Replica Sets"
date: 2027-01-04
categories: [Cloud Computing, Containers]
tags: [docker, health-checks, monitoring, mongodb, container-orchestration, reliability]
---

Docker health checks enable automated monitoring of container health, allowing orchestration systems to detect failures and take corrective action. For MongoDB replica sets, health checks ensure each node responds to database commands and can participate in replication. When a container fails health checks, Docker can restart it or alert monitoring systems, improving overall reliability.

This post demonstrates implementing health checks for the MongoDB replica set from the previous post, inspecting health status, and monitoring container health over time.

## What Are Docker Health Checks?

Health checks are periodic commands Docker executes inside containers to verify they're functioning correctly. A health check can be:

- **healthy**: The check passed
- **unhealthy**: The check failed multiple consecutive times
- **starting**: The container is starting and health checks haven't completed yet

### Why Health Checks Matter

Without health checks, Docker only knows if a container process is running. The process could be alive but:
- Database not accepting connections
- Application deadlocked
- Service in a crash loop
- Network stack unresponsive

Health checks verify the service inside the container is actually functional, not just that the process exists.

### Health Check Lifecycle

1. Container starts → enters **starting** state
2. Docker waits for the first health check
3. If check passes → container becomes **healthy**
4. If check fails → increment failure counter
5. If failures reach `retries` threshold → container becomes **unhealthy**
6. Docker continues running the container (unless orchestrator restarts it)

## Health Check Configuration

Health checks are defined in `docker-compose.yml` or Dockerfiles with five parameters:

- **test**: Command to run (array format)
- **interval**: How often to run the check
- **timeout**: How long to wait for the check to complete
- **retries**: How many consecutive failures before marking unhealthy
- **start_period**: Grace period before starting health checks

### MongoDB-Specific Health Check

For MongoDB, verify the database responds to commands:

```yaml
healthcheck:
  test: ["CMD", "mongosh", "--eval", "db.runCommand('ping').ok"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

**Breakdown**:
- **test**: Runs `mongosh --eval "db.runCommand('ping').ok"` inside the container
  - `db.runCommand('ping')` sends a ping command to MongoDB
  - `.ok` extracts the success field (returns `1` if MongoDB is responsive)
  - Exit code 0 = healthy, non-zero = unhealthy
- **interval**: Check every 30 seconds
- **timeout**: If the check doesn't complete in 10 seconds, it fails
- **retries**: Must fail 3 consecutive times before marking unhealthy
- **start_period**: Wait 40 seconds after container start before beginning checks (allows MongoDB initialization)

## Adding Health Checks to Docker Compose

Update the `docker-compose.yml` from the previous post to include health checks for all three MongoDB nodes.

Edit `docker-compose.yml`:

```yaml
services:
  mongo1:
    build: ./mongo1
    container_name: mongo1
    ports:
      - "27017:27017"
    networks:
      - mongo-network
    volumes:
      - mongo1-data:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.runCommand('ping').ok"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  mongo2:
    build: ./mongo2
    container_name: mongo2
    ports:
      - "27018:27017"
    networks:
      - mongo-network
    volumes:
      - mongo2-data:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.runCommand('ping').ok"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  mongo3:
    build: ./mongo3
    container_name: mongo3
    ports:
      - "27019:27017"
    networks:
      - mongo-network
    volumes:
      - mongo3-data:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.runCommand('ping').ok"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  mongo-network:
    driver: bridge

volumes:
  mongo1-data:
  mongo2-data:
  mongo3-data:
```

## Rebuilding Containers with Health Checks

Stop the existing containers:

```bash
docker compose down
```

Output:

```
[+] Running 4/4
 ✔ Container mongo2                         Removed    10.7s
 ✔ Container mongo3                         Removed    10.7s
 ✔ Container mongo1                         Removed    10.6s
 ✔ Network mongo-replica-set_mongo-network  Removed     0.1s
```

Rebuild and start containers with health checks:

```bash
docker compose up -d --build
```

Output:

```
[+] Building 2.4s (14/14) FINISHED
[+] Running 7/7
 ✔ mongo1  Built       0.0s
 ✔ mongo2  Built       0.0s
 ✔ mongo3  Built       0.0s
 ✔ Network mongo-replica-set_mongo-network  Created  0.1s
 ✔ Container mongo3  Started  1.1s
 ✔ Container mongo1  Started  1.1s
 ✔ Container mongo2  Started  1.0s
```

## Verifying Container Health

Check container status with `docker ps`:

```bash
docker ps
```

Output:

```
CONTAINER ID   IMAGE                      COMMAND                  CREATED          STATUS                    PORTS                                             NAMES
7f043b040a5a   mongo-replica-set-mongo1   "docker-entrypoint.s…"   59 seconds ago   Up 58 seconds (healthy)   0.0.0.0:27017->27017/tcp, [::]:27017->27017/tcp   mongo1
c68c9f92411e   mongo-replica-set-mongo2   "docker-entrypoint.s…"   59 seconds ago   Up 58 seconds (healthy)   0.0.0.0:27018->27017/tcp, [::]:27018->27017/tcp   mongo2
7c1cb7c89aee   mongo-replica-set-mongo3   "docker-entrypoint.s…"   59 seconds ago   Up 58 seconds (healthy)   0.0.0.0:27019->27017/tcp, [::]:27019->27017/tcp   mongo3
```

The **STATUS** column now shows `(healthy)` for all containers, indicating health checks are passing.

## Inspecting Detailed Health Information

Use `docker inspect` to view detailed health check history:

```bash
docker inspect --format='{{json .State.Health}}' mongo1 | jq
```

Output:

```json
{
  "Status": "healthy",
  "FailingStreak": 0,
  "Log": [
    {
      "Start": "2025-02-20T21:43:20.424508434Z",
      "End": "2025-02-20T21:43:21.15201679Z",
      "ExitCode": 0,
      "Output": "1\n"
    },
    {
      "Start": "2025-02-20T21:43:51.161922601Z",
      "End": "2025-02-20T21:43:51.726935115Z",
      "ExitCode": 0,
      "Output": "1\n"
    },
    {
      "Start": "2025-02-20T21:44:21.734994098Z",
      "End": "2025-02-20T21:44:22.205251236Z",
      "ExitCode": 0,
      "Output": "1\n"
    },
    {
      "Start": "2025-02-20T21:44:52.221323146Z",
      "End": "2025-02-20T21:44:52.619633285Z",
      "ExitCode": 0,
      "Output": "1\n"
    },
    {
      "Start": "2025-02-20T21:45:22.634584321Z",
      "End": "2025-02-20T21:45:22.920775616Z",
      "ExitCode": 0,
      "Output": "1\n"
    }
  ]
}
```

**Key Fields**:
- **Status**: Current health state (`healthy`, `unhealthy`, `starting`)
- **FailingStreak**: Consecutive failed checks (0 = all passing)
- **Log**: Recent health check results (up to 5 entries)
  - **ExitCode**: 0 = success, non-zero = failure
  - **Output**: Command output (`1` means MongoDB responded successfully)

Install `jq` for JSON formatting if needed:

```bash
sudo apt install jq
```

## Continuous Health Monitoring

Monitor container health in real-time using `watch`:

```bash
watch -n 2 docker ps
```

Output updates every 2 seconds:

```
Every 2.0s: docker ps

CONTAINER ID   IMAGE                      COMMAND                  CREATED         STATUS                   PORTS                                             NAMES
7f043b040a5a   mongo-replica-set-mongo1   "docker-entrypoint.s…"   6 minutes ago   Up 6 minutes (healthy)   0.0.0.0:27017->27017/tcp, [::]:27017->27017/tcp   mongo1
c68c9f92411e   mongo-replica-set-mongo2   "docker-entrypoint.s…"   6 minutes ago   Up 6 minutes (healthy)   0.0.0.0:27018->27017/tcp, [::]:27018->27017/tcp   mongo2
7c1cb7c89aee   mongo-replica-set-mongo3   "docker-entrypoint.s…"   6 minutes ago   Up 6 minutes (healthy)   0.0.0.0:27019->27017/tcp, [::]:27019->27017/tcp   mongo3
```

Press `Ctrl+C` to exit `watch`.

## Testing Unhealthy State

Simulate a failed health check by stopping MongoDB inside a container without stopping the container itself.

### Stop MongoDB Process Inside Container

Connect to `mongo1`:

```bash
docker exec -it mongo1 bash
```

Inside the container, find the MongoDB process:

```bash
ps aux | grep mongod
```

Kill the MongoDB process:

```bash
kill -9 <PID>
```

Exit the container:

```bash
exit
```

### Observe Health Check Failure

After 3 failed checks (approximately 90 seconds with 30-second intervals), the container becomes unhealthy:

```bash
docker ps
```

Output:

```
CONTAINER ID   IMAGE                      COMMAND                  CREATED          STATUS                      PORTS
7f043b040a5a   mongo-replica-set-mongo1   "docker-entrypoint.s…"   10 minutes ago   Up 10 minutes (unhealthy)   0.0.0.0:27017->27017/tcp   mongo1
```

The container shows `(unhealthy)` status.

### Inspect Failed Health Checks

```bash
docker inspect --format='{{json .State.Health}}' mongo1 | jq
```

Output shows failed checks:

```json
{
  "Status": "unhealthy",
  "FailingStreak": 3,
  "Log": [
    {
      "Start": "2025-02-20T22:10:15.123456789Z",
      "End": "2025-02-20T22:10:25.234567890Z",
      "ExitCode": 1,
      "Output": "Error: MongoDB connection failed\n"
    },
    ...
  ]
}
```

### Restart the Unhealthy Container

Docker doesn't automatically restart containers on health check failure (unless using orchestrators like Docker Swarm or Kubernetes). Restart manually:

```bash
docker restart mongo1
```

After the container restarts and MongoDB initializes, health checks pass again:

```bash
docker ps
```

Output:

```
7f043b040a5a   mongo-replica-set-mongo1   ...   Up 2 minutes (healthy)   ...   mongo1
```

## Integrating Health Checks with Orchestration

### Docker Swarm

In Docker Swarm mode, unhealthy containers automatically restart:

```yaml
deploy:
  replicas: 1
  restart_policy:
    condition: on-failure
```

### Kubernetes

Kubernetes uses liveness and readiness probes (similar to health checks):

```yaml
livenessProbe:
  exec:
    command:
      - mongosh
      - --eval
      - db.runCommand('ping').ok
  initialDelaySeconds: 40
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3
```

### Monitoring Systems

Export health check status to monitoring systems like Prometheus:

1. Use an exporter to scrape Docker API
2. Collect health check metrics
3. Alert when containers become unhealthy

## Advanced Health Check Patterns

### Replica Set-Aware Health Check

Check if the node is in a valid replica set state:

```yaml
healthcheck:
  test: ["CMD", "mongosh", "--eval", "rs.status().ok && (rs.status().myState === 1 || rs.status().myState === 2)"]
```

This verifies the node is either PRIMARY (1) or SECONDARY (2).

### Application-Level Health Check

For applications using MongoDB, check both database and application health:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
```

The `/health` endpoint verifies database connectivity and application logic.

### Dependency-Aware Health Checks

Use `depends_on` with health checks to ensure dependent services start only when dependencies are healthy:

```yaml
services:
  app:
    depends_on:
      mongo1:
        condition: service_healthy
```

## Common Issues and Troubleshooting

### Health Checks Always Failing

If health checks never pass:

1. **Verify the command works manually**:
   ```bash
   docker exec mongo1 mongosh --eval "db.runCommand('ping').ok"
   ```

2. **Increase start_period** if MongoDB takes longer to initialize:
   ```yaml
   start_period: 60s
   ```

3. **Check timeout** isn't too short:
   ```yaml
   timeout: 15s
   ```

### Container Status Stuck in "starting"

If containers remain in "starting" state:

- Health check hasn't completed successfully yet
- Increase `start_period` or reduce `interval`
- Check health check logs: `docker inspect <container>`

### False Positives (Unhealthy When Actually Healthy)

If healthy containers marked unhealthy:

- Network latency may cause timeouts
- Increase `timeout` value
- Reduce `interval` to get results faster
- Adjust `retries` to allow more failures

## Viewing Health Check Logs

Docker stores the last 5 health check results. For older results, use container logs:

```bash
docker logs mongo1 2>&1 | grep healthcheck
```

Or configure logging drivers to send health check events to external systems.

## What's Next

With health checks monitoring container health, the infrastructure is more reliable and self-healing. The next posts transition to Ansible, demonstrating how to automate the deployment and configuration of containerized applications and cloud infrastructure using infrastructure-as-code principles.

## Summary

This post covered:

- Docker health check fundamentals and lifecycle
- Why health checks matter for reliability
- Health check configuration parameters (test, interval, timeout, retries, start_period)
- MongoDB-specific health check using mongosh ping command
- Adding health checks to Docker Compose for all replica set nodes
- Rebuilding containers with health checks enabled
- Verifying container health with docker ps
- Inspecting detailed health information with docker inspect and jq
- Continuous monitoring with watch command
- Testing unhealthy state by stopping MongoDB process
- Observing health check failure and recovery
- Restarting unhealthy containers
- Integration with orchestration systems (Swarm, Kubernetes)
- Advanced health check patterns (replica set state, application-level, dependencies)
- Troubleshooting always-failing checks, stuck containers, false positives
- Viewing health check logs

Docker health checks now provide automated monitoring for the MongoDB replica set, enabling proactive detection and recovery from failures. In the next post, we'll introduce Ansible for automating infrastructure deployment and configuration management.
