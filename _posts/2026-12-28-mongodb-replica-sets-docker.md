---
title: "Building MongoDB Replica Sets with Docker Compose"
date: 2026-12-28
categories: [Cloud Computing, Containers]
tags: [docker, docker-compose, mongodb, replica-set, high-availability, database, replication]
---

MongoDB replica sets provide high availability and data redundancy through automatic replication across multiple database instances. When one node fails, another automatically becomes primary, ensuring continuous service. Docker simplifies deploying replica sets by containerizing each MongoDB instance and orchestrating them with Docker Compose.

This post demonstrates building a production-ready MongoDB replica set with three nodes, automatic replication, and failover capabilities using Docker.

## What is a MongoDB Replica Set?

A replica set is a group of MongoDB instances that maintain the same dataset. The set consists of:

- **Primary**: Accepts all write operations and replicates changes to secondaries
- **Secondary** (multiple): Replicate data from the primary and can serve read operations
- **Arbiter** (optional): Votes in elections but doesn't store data

### Benefits of Replica Sets

1. **High Availability**: Automatic failover if primary goes down
2. **Data Redundancy**: Multiple copies protect against hardware failure
3. **Read Scaling**: Distribute read operations across secondaries
4. **Disaster Recovery**: Geographic distribution of nodes
5. **Zero-Downtime Maintenance**: Take nodes offline without service interruption

### How Replication Works

1. Application writes data to the primary
2. Primary records the operation in its oplog (operations log)
3. Secondaries asynchronously copy and apply oplog entries
4. If the primary fails, secondaries hold an election and elect a new primary
5. Applications reconnect to the new primary automatically

## Architecture Overview

This deployment creates three MongoDB containers:

- **mongo1**: Primary node (initially)
- **mongo2**: Secondary node
- **mongo3**: Secondary node

All nodes connect to a shared Docker network (`mongo-network`) and persist data in named volumes. Each node runs the same MongoDB version configured for replica set `rs0`.

## Creating the Project Structure

Create a project directory and file structure:

```bash
mkdir mongo-replica-set
cd mongo-replica-set
touch docker-compose.yml
mkdir -p mongo1 mongo2 mongo3
touch mongo{1..3}/Dockerfile
```

Verify the structure:

```bash
tree
```

Output:

```
.
└── mongo-replica-set
    ├── docker-compose.yml
    ├── mongo1
    │   └── Dockerfile
    ├── mongo2
    │   └── Dockerfile
    └── mongo3
        └── Dockerfile

5 directories, 4 files
```

This structure separates configuration for each MongoDB node, allowing customization if needed.

## Creating Dockerfiles

Each MongoDB node uses the same Dockerfile. Create identical content in `mongo1/Dockerfile`, `mongo2/Dockerfile`, and `mongo3/Dockerfile`:

```dockerfile
FROM mongo:latest
EXPOSE 27017
CMD ["mongod", "--replSet", "rs0", "--bind_ip_all"]
```

**Breakdown**:
- `FROM mongo:latest`: Use the official MongoDB image as the base
- `EXPOSE 27017`: Document that MongoDB listens on port 27017
- `CMD`: Start MongoDB with replica set name `rs0` and bind to all network interfaces

The `--bind_ip_all` flag allows MongoDB to accept connections from any IP address on the Docker network, which is necessary for replica set communication between containers.

## Creating Docker Compose Configuration

Edit `docker-compose.yml`:

```yaml
services:  # Defines the services (containers) that will be started.

  mongo1:  # First MongoDB instance
    build: ./mongo1         # Builds the image from the `mongo1` directory.
    container_name: mongo1  # Explicitly names the container `mongo1`.
    ports:
      - "27017:27017"       # Maps port 27017 on the host to port 27017 in the container.
    networks:
      - mongo-network       # Connects this container to the `mongo-network`.
    volumes:
      - mongo1-data:/data/db  # Persists MongoDB data in a named volume.

  mongo2:  # Second MongoDB instance
    build: ./mongo2         # Builds the image from the `mongo2` directory.
    container_name: mongo2  # Explicitly names the container `mongo2`.
    ports:
      - "27018:27017"       # Maps port 27018 on the host to port 27017 in the container.
    networks:
      - mongo-network       # Connects this container to the `mongo-network`.
    volumes:
      - mongo2-data:/data/db  # Persists MongoDB data in a named volume.

  mongo3:  # Third MongoDB instance
    build: ./mongo3         # Builds the image from the `mongo3` directory.
    container_name: mongo3  # Explicitly names the container `mongo3`.
    ports:
      - "27019:27017"       # Maps port 27019 on the host to port 27017 in the container.
    networks:
      - mongo-network       # Connects this container to the `mongo-network`.
    volumes:
      - mongo3-data:/data/db  # Persists MongoDB data in a named volume.

networks:  # Defines the network configuration.
  mongo-network:
    driver: bridge          # Uses a bridge network for inter-container communication.

volumes:  # Defines persistent volumes for MongoDB instances.
  mongo1-data:  # Volume for `mongo1` to store data persistently.
  mongo2-data:  # Volume for `mongo2` to ensure data is not lost.
  mongo3-data:  # Volume for `mongo3` to maintain database continuity.
```

**Key Points**:
- Each MongoDB instance exposes a different host port (27017, 27018, 27019) but all use 27017 internally
- All containers share the `mongo-network` bridge network, enabling communication using container names
- Named volumes persist data outside containers, surviving container restarts and removals
- Container names (`mongo1`, `mongo2`, `mongo3`) serve as hostnames within the Docker network

## Starting the MongoDB Containers

Build and start all services:

```bash
docker compose up -d
```

Output:

```
[+] Building 15.2s (12/12) FINISHED
[+] Running 4/4
 ✔ Network mongo-replica-set_mongo-network  Created
 ✔ Container mongo1                         Started
 ✔ Container mongo2                         Started
 ✔ Container mongo3                         Started
```

The `-d` flag runs containers in detached mode (background).

Verify containers are running:

```bash
docker compose ps
```

Output:

```
NAME     IMAGE                         COMMAND                  SERVICE   CREATED         STATUS         PORTS
mongo1   mongo-replica-set-mongo1      "docker-entrypoint.s…"   mongo1    2 minutes ago   Up 2 minutes   0.0.0.0:27017->27017/tcp
mongo2   mongo-replica-set-mongo2      "docker-entrypoint.s…"   mongo2    2 minutes ago   Up 2 minutes   0.0.0.0:27018->27017/tcp
mongo3   mongo-replica-set-mongo3      "docker-entrypoint.s…"   mongo3    2 minutes ago   Up 2 minutes   0.0.0.0:27019->27017/tcp
```

All three MongoDB instances are running.

## Initializing the Replica Set

MongoDB containers are running but not yet configured as a replica set. Connect to `mongo1` and initialize the replica set.

### Connect to the Primary (mongo1)

```bash
docker exec -it mongo1 mongosh
```

You'll enter the MongoDB shell:

```
Current Mongosh Log ID: 67b7977ad88addb69c544ca6
Connecting to:          mongodb://127.0.0.1:27017/?directConnection=true&serverSelectionTimeoutMS=2000&appName=mongosh+2.3.8
Using MongoDB:          8.0.4
Using Mongosh:          2.3.8
```

### Initialize the Replica Set

Run the `rs.initiate()` command with the replica set configuration:

```javascript
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "mongo1:27017" },
    { _id: 1, host: "mongo2:27017" },
    { _id: 2, host: "mongo3:27017" }
  ]
});
```

Output:

```javascript
{
  ok: 1,
  '$clusterTime': {
    clusterTime: Timestamp({ t: 1740085241, i: 1 }),
    signature: {
      hash: Binary.createFromBase64('AAAAAAAAAAAAAAAAAAAAAAAAAAA=', 0),
      keyId: Long('0')
    }
  },
  operationTime: Timestamp({ t: 1740085241, i: 1 })
}
```

The `ok: 1` response indicates successful initialization. After a few seconds, the prompt changes:

```
rs0 [direct: secondary] test>
```

Then:

```
rs0 [direct: primary] test>
```

The node transitioned from secondary to primary after the election.

### Verify Replica Set Status

Check the replica set configuration:

```javascript
rs.status();
```

Key output sections:

```javascript
{
  set: 'rs0',
  myState: 1,  // 1 = PRIMARY
  members: [
    {
      _id: 0,
      name: 'mongo1:27017',
      health: 1,
      state: 1,
      stateStr: 'PRIMARY',
      self: true
    },
    {
      _id: 1,
      name: 'mongo2:27017',
      health: 1,
      state: 2,
      stateStr: 'SECONDARY'
    },
    {
      _id: 2,
      name: 'mongo3:27017',
      health: 1,
      state: 2,
      stateStr: 'SECONDARY'
    }
  ],
  ok: 1
}
```

The replica set is operational:
- `mongo1` is PRIMARY
- `mongo2` and `mongo3` are SECONDARY
- All nodes have `health: 1` (healthy)

## Testing Replication

Insert data on the primary and verify it replicates to secondaries.

### Insert Data on Primary (mongo1)

Still connected to `mongo1` in the MongoDB shell:

```javascript
use testdb;
db.testCollection.insertOne({
  name: "Rick Sanchez",
  message: "Wubba Lubba Dub Dub! Time to replicate some data, Morty!"
});

db.testCollection.insertOne({
  name: "GLaDOS",
  message: "Replication successful. You monster."
});

db.testCollection.insertOne({
  name: "HAL 9000",
  message: "I'm sorry, Dave. I'm afraid I can't let you lose this assignment."
});

db.testCollection.insertOne({
  name: "Yoda",
  message: "Replicate, this database must. Fail, you must not."
});
```

Exit the MongoDB shell:

```javascript
exit
```

### Verify Replication on Secondary (mongo2)

Connect to `mongo2`:

```bash
docker exec -it mongo2 mongosh
```

In the MongoDB shell:

```javascript
use testdb;
db.testCollection.find();
```

Output:

```javascript
[
  {
    _id: ObjectId('67b7998a8b99d8401a544ca7'),
    name: 'Rick Sanchez',
    message: 'Wubba Lubba Dub Dub! Time to replicate some data, Morty!'
  },
  {
    _id: ObjectId('67b7998b8b99d8401a544ca8'),
    name: 'GLaDOS',
    message: 'Replication successful. You monster.'
  },
  {
    _id: ObjectId('67b7998b8b99d8401a544ca9'),
    name: 'HAL 9000',
    message: "I'm sorry, Dave. I'm afraid I can't let you lose this assignment."
  },
  {
    _id: ObjectId('67b7998b8b99d8401a544caa'),
    name: 'Yoda',
    message: 'Replicate, this database must. Fail, you must not.'
  }
]
```

The data inserted on `mongo1` (primary) automatically replicated to `mongo2` (secondary).

Exit and verify on `mongo3`:

```bash
docker exec -it mongo3 mongosh
use testdb
db.testCollection.find();
```

The same data appears on `mongo3`. **Replication is working correctly.**

## Testing Automatic Failover

Simulate a primary failure to demonstrate automatic failover.

### Stop the Primary (mongo1)

```bash
docker stop mongo1
```

### Check Replica Set Status from Secondary

Connect to `mongo2`:

```bash
docker exec -it mongo2 mongosh
```

Check the replica set status:

```javascript
rs.status();
```

After a few seconds (election timeout), one of the secondaries becomes the new primary. Example output:

```javascript
{
  members: [
    {
      _id: 0,
      name: 'mongo1:27017',
      health: 0,      // Down
      state: 8,
      stateStr: '(not reachable/healthy)'
    },
    {
      _id: 1,
      name: 'mongo2:27017',
      health: 1,
      state: 1,        // New primary
      stateStr: 'PRIMARY',
      self: true
    },
    {
      _id: 2,
      name: 'mongo3:27017',
      health: 1,
      state: 2,
      stateStr: 'SECONDARY'
    }
  ]
}
```

`mongo2` is now the primary. The replica set remains available despite `mongo1` being down.

### Restart mongo1

```bash
docker start mongo1
```

Connect to `mongo1`:

```bash
docker exec -it mongo1 mongosh
rs.status();
```

`mongo1` rejoins the replica set as a secondary:

```javascript
{
  _id: 0,
  name: 'mongo1:27017',
  health: 1,
  state: 2,
  stateStr: 'SECONDARY'
}
```

The replica set automatically rebalances. `mongo1` catches up by replicating missed operations from the oplog.

## Common Issues and Troubleshooting

### Replica Set Initialization Fails

If `rs.initiate()` returns errors:

1. **Verify all containers are running**:
   ```bash
   docker compose ps
   ```

2. **Check network connectivity**:
   ```bash
   docker exec -it mongo1 ping mongo2
   ```

3. **Verify hostnames resolve**:
   ```bash
   docker network inspect mongo-replica-set_mongo-network
   ```

### Secondary Nodes Don't Replicate

If data doesn't appear on secondaries:

1. **Check replica set status** on primary:
   ```javascript
   rs.status();
   ```

2. **Verify secondary nodes are in SECONDARY state**, not STARTUP or RECOVERING

3. **Check oplog**:
   ```javascript
   use local;
   db.oplog.rs.find().limit(10);
   ```

### "not master and slaveOk=false" Error on Secondary

Secondaries don't allow reads by default. Enable reads:

```javascript
rs.secondaryOk();
```

Or in modern MongoDB:

```javascript
db.getMongo().setReadPref('secondary');
```

### Containers Keep Restarting

Check container logs:

```bash
docker logs mongo1
docker logs mongo2
docker logs mongo3
```

Common issues:
- Port conflicts (another service using 27017/27018/27019)
- Insufficient disk space for volumes
- Memory constraints

## Managing the Replica Set

### View Replica Set Configuration

```javascript
rs.conf();
```

### Add a Node

```javascript
rs.add("mongo4:27017");
```

### Remove a Node

```javascript
rs.remove("mongo3:27017");
```

### Force a Specific Primary

```javascript
rs.stepDown();  // Force current primary to step down
```

### Check Replication Lag

```javascript
rs.printSecondaryReplicationInfo();
```

## Stopping and Cleaning Up

### Stop All Containers

```bash
docker compose down
```

This stops and removes containers but preserves volumes.

### Remove Volumes (Delete All Data)

```bash
docker compose down -v
```

The `-v` flag removes named volumes, permanently deleting all MongoDB data.

## What's Next

With a working MongoDB replica set, the next post covers Docker health checks and monitoring to ensure replica set availability and detect issues before they impact applications.

## Summary

This post covered:

- MongoDB replica set architecture and benefits
- Primary, secondary, and arbiter roles
- Automatic failover and replication mechanics
- Creating project structure for Docker Compose deployment
- Writing Dockerfiles for MongoDB with replica set configuration
- Docker Compose YAML for three-node replica set
- Starting MongoDB containers with docker compose
- Initializing the replica set with rs.initiate()
- Verifying replica set status and member roles
- Testing data replication across all nodes
- Simulating failover by stopping the primary
- Automatic election of new primary
- Rejoining nodes after restart
- Troubleshooting initialization, replication, and connectivity issues
- Managing replica sets (adding/removing nodes, forcing elections)

A production-ready MongoDB replica set is now running in Docker containers with automatic replication and failover. In the next post, we'll implement health checks and monitoring to ensure the replica set remains healthy and available.
