# Local Kafka – SASL/SCRAM-SHA-512 (over SASL_PLAINTEXT)

A single-node local Kafka (KRaft, no ZooKeeper) secured with **SASL/SCRAM-SHA-512**, used to test the Open Streaming path:

```
ADS  ──►  Bridge Service  ──►  Kafka (localhost:9094, SCRAM-SHA-512)  ──►  ATLAS
```

---

## Contents

1. [How this setup works](#1-how-this-setup-works)
2. [Folder structure](#2-folder-structure)
3. [What are `admin.properties` and `scram-client.properties`?](#3-what-are-adminproperties-and-scram-clientproperties)
4. [Files](#4-files)
5. [Setup steps](#5-setup-steps)
6. [Bridge Service and ATLAS configuration](#6-bridge-service-and-atlas-configuration)
7. [Verification tests](#7-verification-tests)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. How this setup works

### PLAIN vs SCRAM-SHA-512

| | SASL/PLAIN | SASL/SCRAM-SHA-512 |
|---|---|---|
| Where users are stored | `user_xxx=` lines in `kafka_server_jaas.conf` | Kafka metadata log, created with `kafka-configs.sh` |
| Password on the wire | Sent as-is | Never sent – challenge/response with salted hash |
| Adding a user | Edit JAAS file + restart broker | One command, no restart |

### Listener design

The broker exposes two SASL listeners, each allowing a different mechanism:

| Listener | Address | Used by | Mechanism |
|---|---|---|---|
| `SASL_INTERNAL` | `kafka:9092` | Broker-to-broker, Kafka UI, admin commands | **PLAIN** (`admin`) |
| `SASL_HOST` | `localhost:9094` | Bridge Service, ATLAS, test clients on Windows | **SCRAM-SHA-512** (`streamuser`) |
| `CONTROLLER` | `kafka:9093` | KRaft controller only | none |

**Why keep PLAIN internally?** SCRAM users live inside Kafka's own metadata, so they can only be created *after* the broker is running. If the broker itself needed a SCRAM user to start, it could never start. PLAIN for `admin` (defined in the JAAS file) solves this bootstrap problem.

**Why SCRAM only on 9094?** So ADS/ATLAS cannot silently fall back to PLAIN – a successful connection on 9094 proves SCRAM is working.

### Topic naming (TopicBased)

The Bridge builds topic names from its configuration, and Kafka auto-creates them on first publish:

```
<Domain>.Data.<DataSource>.<Stream>   →   Testing.Data.Default.Live
```

Other topics created automatically: `Testing.Data.Default`, `Testing.Essentials.Default`, `Testing.System.SessionInfo`.

`KAFKA_NUM_PARTITIONS: 1` is used so every auto-created topic has a single partition. With more partitions in TopicBased mode, the producer may place records in any partition (0, 1 or 2), which is confusing when checking Kafka UI.

---

## 2. Folder structure

```
SASL_SCRAM512/
├── README.md
├── docker-compose.yml
├── kafka_server_jaas.conf
├── admin.properties
└── scram-client.properties
```

---

## 3. What are `admin.properties` and `scram-client.properties`?

Kafka's command-line tools (`kafka-configs.sh`, `kafka-topics.sh`, `kafka-console-producer.sh`, …) are **Kafka clients**, just like the Bridge or ATLAS. On a secured broker, every client must say:

1. **Which security protocol** to use → `security.protocol`
2. **Which SASL mechanism** to use → `sasl.mechanism`
3. **Who it is** (username + password) → `sasl.jaas.config`

Instead of typing these on every command, they are stored in a `.properties` file and passed with `--command-config` (or `--producer.config` / `--consumer.config`).

Without such a file, the CLI tries to connect with no authentication and the broker rejects it.

### `admin.properties` – the administrator identity

```properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="admin-secret";
```

| Purpose | Details |
|---|---|
| Who | `admin`, defined in `kafka_server_jaas.conf` |
| Where | Internal listener `kafka:9092` |
| Mechanism | PLAIN |
| Used for | Creating, listing, updating and deleting **SCRAM users** |

It is needed because a SCRAM user can't be created by a SCRAM user that doesn't exist yet – an already-trusted identity (admin over PLAIN) must do it.

### `scram-client.properties` – the application identity

```properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="streamuser" password="stream-secret";
```

| Purpose | Details |
|---|---|
| Who | `streamuser`, created with `kafka-configs.sh` |
| Where | Host listener `localhost:9094` |
| Mechanism | SCRAM-SHA-512 |
| Used for | Proving SCRAM works **before** testing the Bridge – listing topics, producing and consuming |

It uses exactly the same credentials and mechanism as the Bridge and ATLAS. If the CLI works with this file but the Bridge doesn't, the problem is in the Bridge configuration, not Kafka.

### How the flow works

```
                    admin.properties (PLAIN)
  kafka-configs.sh ─────────────────────────► kafka:9092
        │                                        │
        │  "create SCRAM-SHA-512 user streamuser" │
        └────────────────────────────────────────►  stored in Kafka metadata log
                                                   (salted hash, not the password)

                    scram-client.properties (SCRAM-SHA-512)
  kafka-topics.sh  ─────────────────────────► localhost:9094
  Bridge Service   ─────────────────────────► localhost:9094   same credentials
  ATLAS            ─────────────────────────► localhost:9094
```

### SCRAM handshake (simplified)

1. Client sends its username and a random nonce.
2. Broker looks up the user's **salt** and **iteration count** and returns them with its own nonce.
3. Client computes a proof from the password, salt and nonces, and sends the proof – **not the password**.
4. Broker verifies the proof against the stored hash and replies with its own proof, so the client also verifies the broker.

> These `.properties` files are only for CLI tools. The Bridge uses its JSON `Security` block, and ATLAS uses its Stream Configuration dialog – but all three express the same three settings.

---

## 4. Files

### `kafka_server_jaas.conf`

```properties
KafkaServer {
  org.apache.kafka.common.security.plain.PlainLoginModule required
  username="admin"
  password="admin-secret"
  user_admin="admin-secret";

  org.apache.kafka.common.security.scram.ScramLoginModule required;
};
```

- `username`/`password` – identity the broker uses for inter-broker traffic.
- `user_admin` – PLAIN user accepted by the broker.
- `ScramLoginModule` – enables SCRAM; its users are **not** listed here.

### `docker-compose.yml`

```yaml
name: kafka-scram-local

services:
  kafka:
    image: apache/kafka:4.1.0
    hostname: kafka
    container_name: kafka-broker-1
    ports:
      - "9094:9094"
    environment:
      CLUSTER_ID: "MkU3OEVBNTcwNTJENDM2Qk"
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: "broker,controller"
      KAFKA_CONTROLLER_QUORUM_VOTERS: "1@kafka:9093"
      KAFKA_CONTROLLER_LISTENER_NAMES: "CONTROLLER"

      KAFKA_LISTENERS: "SASL_INTERNAL://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093,SASL_HOST://0.0.0.0:9094"
      KAFKA_ADVERTISED_LISTENERS: "SASL_INTERNAL://kafka:9092,SASL_HOST://localhost:9094"
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: "CONTROLLER:PLAINTEXT,SASL_INTERNAL:SASL_PLAINTEXT,SASL_HOST:SASL_PLAINTEXT"
      KAFKA_INTER_BROKER_LISTENER_NAME: "SASL_INTERNAL"

      KAFKA_SASL_ENABLED_MECHANISMS: "PLAIN,SCRAM-SHA-512"
      KAFKA_SASL_MECHANISM_INTER_BROKER_PROTOCOL: "PLAIN"
      KAFKA_LISTENER_NAME_SASL_INTERNAL_SASL_ENABLED_MECHANISMS: "PLAIN"
      KAFKA_LISTENER_NAME_SASL_HOST_SASL_ENABLED_MECHANISMS: "SCRAM-SHA-512"

      KAFKA_OPTS: "-Djava.security.auth.login.config=/etc/kafka/kafka_server_jaas.conf"

      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
      KAFKA_NUM_PARTITIONS: 1
      KAFKA_LOG_DIRS: "/tmp/kraft-kafka-logs"
    volumes:
      - ./kafka_server_jaas.conf:/etc/kafka/kafka_server_jaas.conf:ro
      - kafka_data:/tmp/kraft-kafka-logs   # keeps SCRAM users across restarts
    networks: [kafka_net_internal]

  kafka-ui:
    image: provectuslabs/kafka-ui:latest
    container_name: kafka-ui-1
    ports:
      - "8080:8080"
    environment:
      KAFKA_CLUSTERS_0_NAME: "local-scram-kafka"
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: "kafka:9092"
      KAFKA_CLUSTERS_0_PROPERTIES_SECURITY_PROTOCOL: "SASL_PLAINTEXT"
      KAFKA_CLUSTERS_0_PROPERTIES_SASL_MECHANISM: "PLAIN"
      KAFKA_CLUSTERS_0_PROPERTIES_SASL_JAAS_CONFIG: >-
        org.apache.kafka.common.security.plain.PlainLoginModule required
        username="admin" password="admin-secret";
      DYNAMIC_CONFIG_ENABLED: "true"
    depends_on: [kafka]
    networks: [kafka_net_internal]

networks:
  kafka_net_internal:
    driver: bridge

volumes:
  kafka_data:
```

> SCRAM users are stored in the broker's metadata log. The `kafka_data` volume keeps them across restarts. `docker compose down -v` deletes the volume **and the users**.

---

## 5. Setup steps

Run in PowerShell from the `SASL_SCRAM512` folder.

### Step 1 – Create the properties files

```powershell
@'
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="admin-secret";
'@ | Set-Content -Path .\admin.properties -Encoding ascii

@'
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="streamuser" password="stream-secret";
'@ | Set-Content -Path .\scram-client.properties -Encoding ascii
```

> Use `-Encoding ascii`. In Windows PowerShell 5, `utf8` adds a BOM that Java misreads. The closing `'@` must start at column 1.

### Step 2 – Start Kafka

```powershell
docker compose up -d
docker compose logs kafka --tail 50
```

### Step 3 – Copy the properties files into the container

```powershell
docker cp .\admin.properties kafka-broker-1:/tmp/admin.properties
docker cp .\scram-client.properties kafka-broker-1:/tmp/scram-client.properties
docker exec kafka-broker-1 ls -l /tmp/admin.properties /tmp/scram-client.properties
```

> Files copied into `/tmp` are lost whenever the container is recreated. Repeat this step after `docker compose up --force-recreate` or `down`/`up`.

### Step 4 – Create the SCRAM user

```powershell
docker exec kafka-broker-1 sh -c "/opt/kafka/bin/kafka-configs.sh --bootstrap-server kafka:9092 --command-config /tmp/admin.properties --alter --add-config 'SCRAM-SHA-512=[iterations=8192,password=stream-secret]' --entity-type users --entity-name streamuser"
```

Expected: `Completed updating config for user streamuser.`

`sh -c "..."` lets the Linux shell inside the container handle quoting, so this works the same from PowerShell or cmd.

### Step 5 – Verify the user

```powershell
docker exec kafka-broker-1 sh -c "/opt/kafka/bin/kafka-configs.sh --bootstrap-server kafka:9092 --command-config /tmp/admin.properties --describe --entity-type users --entity-name streamuser"
```

Expected: `SCRAM credential configs for user-principal 'streamuser' are SCRAM-SHA-512=iterations=8192`

The password is never shown – Kafka only stores a salted hash.

### Managing users

```powershell
# Change password
docker exec kafka-broker-1 sh -c "/opt/kafka/bin/kafka-configs.sh --bootstrap-server kafka:9092 --command-config /tmp/admin.properties --alter --add-config 'SCRAM-SHA-512=[password=new-secret]' --entity-type users --entity-name streamuser"

# Delete user
docker exec kafka-broker-1 sh -c "/opt/kafka/bin/kafka-configs.sh --bootstrap-server kafka:9092 --command-config /tmp/admin.properties --alter --delete-config 'SCRAM-SHA-512' --entity-type users --entity-name streamuser"

# List all SCRAM users
docker exec kafka-broker-1 sh -c "/opt/kafka/bin/kafka-configs.sh --bootstrap-server kafka:9092 --command-config /tmp/admin.properties --describe --entity-type users"
```

---

## 6. Bridge Service and ATLAS configuration

### Bridge Service (`StreamApiConfig`)

```json
"StreamApiConfig": {
  "StreamCreationStrategy": 2,
  "BrokerUrl": "localhost:9094",
  "Domain": "Testing",
  "Security": {
    "Protocol": "SaslPlaintext",
    "Mechanism": "ScramSha512",
    "SaslUsername": "streamuser",
    "SaslPassword": "stream-secret"
  }
}
```

- `StreamCreationStrategy: 2` = TopicBased, `1` = PartitionBased.
- Restart the Bridge after any config change – it reads the config only at startup.

### ATLAS Stream Configuration

| Field | Value |
|---|---|
| Broker URL | `localhost:9094` |
| Domain Name | `Testing` |
| Stream Creation Strategy | `TopicBased` (no partition mapping) |
| Security Protocol | SASL Plaintext |
| Security Mechanism | SCRAM-SHA-512 |
| SASL Username / Password | `streamuser` / `stream-secret` |

### Which address to use

| Client runs… | Use |
|---|---|
| On Windows host (Bridge, ATLAS, CLI via `localhost`) | `localhost:9094` |
| In a container on `kafka_net_internal` | `kafka:9092` (PLAIN listener) |

---

## 7. Verification tests

All three must behave as expected to prove SCRAM is enforced.

| # | Test | Expected |
|---|---|---|
| 1 | Correct SCRAM credentials | ✅ Topics listed (or empty list, no error) |
| 2 | Wrong password | ❌ `Authentication failed ... invalid credentials with SASL mechanism SCRAM-SHA-512` |
| 3 | PLAIN on port 9094 | ❌ `Unsupported SASL mechanism PLAIN` |

### Test 1 – correct credentials

```powershell
docker exec kafka-broker-1 sh -c "/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9094 --command-config /tmp/scram-client.properties --list"
```

### Test 2 – wrong password

```powershell
docker exec kafka-broker-1 sh -c "sed 's/stream-secret/wrong/' /tmp/scram-client.properties > /tmp/wrong.properties && /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9094 --command-config /tmp/wrong.properties --list"
```

### Test 3 – PLAIN rejected on 9094

```powershell
docker exec kafka-broker-1 sh -c "/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9094 --command-config /tmp/admin.properties --list"
```

### Produce / consume

```powershell
# Terminal 1 – consumer
docker exec -it kafka-broker-1 /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9094 --consumer.config /tmp/scram-client.properties --topic scram-test --from-beginning

# Terminal 2 – producer (type a message and press Enter)
docker exec -it kafka-broker-1 /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9094 --producer.config /tmp/scram-client.properties --topic scram-test
```

### End-to-end

1. Start the Bridge – log should **not** show `Kafka is not available`.
2. Connect ATLAS (TopicBased, SCRAM credentials).
3. Replay from ADS.
4. In Kafka UI (`http://localhost:8080`) check `Testing.Data.Default.Live` grows and the ATLAS consumer group appears under **Consumers**.

---

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `invalid credentials with SASL mechanism SCRAM-SHA-512` | SCRAM user missing (never created, or container/volume recreated) or wrong password | Step 5 to check, Step 4 to create |
| `Unsupported SASL mechanism` | Client sends PLAIN or SCRAM-SHA-256 | Set mechanism to SCRAM-SHA-512 / `ScramSha512` |
| `NoSuchFileException: /tmp/admin.properties` | File not copied into container | Step 1 then Step 3 |
| `GetFileAttributesEx ... cannot find the file` | `admin.properties` not in current folder | Run Step 1 in the `SASL_SCRAM512` folder |
| Admin command fails to authenticate | Wrong JAAS file mounted | `docker exec kafka-broker-1 cat /etc/kafka/kafka_server_jaas.conf` – must contain `user_admin` |
| CLI works, Bridge fails | Bridge config wrong or not reloaded | Check `Security` block, remove template values (`myuser`), restart Bridge |
| Bridge connects, ATLAS shows no data | Not a security issue | Check Domain matches, ATLAS is TopicBased, start ATLAS before replay |
| Data in partition 1 or 2 instead of 0 | Topic created with >1 partitions; producer partitioner choice | Use `KAFKA_NUM_PARTITIONS: 1`, delete topics, replay |

### Useful commands

```powershell
docker compose ps
docker compose logs kafka | Select-String -Pattern "sasl|scram|error|exception"
docker compose down          # stop, keep SCRAM users
docker compose down -v       # stop and DELETE all data and SCRAM users
```

---

## Credentials summary (local only)

| User | Password | Mechanism | Defined in | Listener |
|---|---|---|---|---|
| `admin` | `admin-secret` | PLAIN | `kafka_server_jaas.conf` | `kafka:9092` |
| `streamuser` | `stream-secret` | SCRAM-SHA-512 | Kafka metadata (`kafka-configs.sh`) | `localhost:9094` |

> Do not commit real credentials. These values are for local testing only.
