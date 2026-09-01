# Open-Streaming

This repository includes comprehensive setup configurations for Kafka with various security authentication mechanisms. It provides Docker-based environments for testing different security protocols and integration examples.

## Table of Contents

- [Which setup do I want?](#which-setup-do-i-want)
- [Quick Start](#quick-start)
- [Available Security Configurations](#available-security-configurations)
- [Setup Guides](#setup-guides)
- [Docker Swarm deployment](#docker-swarm-deployment)
- [Directory Structure](#directory-structure)
- [Common Prerequisites](#common-prerequisites)

---

## Which setup do I want?

There are two deployment modes in this repo. They test the same five security
postures but are built for different environments — pick one before reading on.

| | `test/` — single-node Compose | `swarm/` — multi-node Swarm |
|---|---|---|
| **Runs on** | One machine, `docker compose` | Docker Swarm, nodes labelled `role=kafka` / `role=bridge` |
| **Shape** | Five separate stacks, one per scenario | **One** stack exposing all five postures on different ports |
| **Switching scenario** | Tear down, bring up the next | Change the client's port + `Security` block |
| **Existing plaintext broker** | Replaced | **Left running untouched** |
| **Best for** | Learning a posture in isolation; quick local experiments | Testing against the real deployment without downtime |

If you are validating the **Stream API / Bridge Service security feature against
the real cluster**, go to **[`swarm/`](swarm/SWARM_SETUP_GUIDE.md)**.

> **Swarm users — three things in `test/` do not carry over.** `docker stack deploy`
> ignores `container_name` and `depends_on`; relative bind mounts such as
> `./secrets` are not copied to remote nodes; and the SCRAM scenario's
> `kafka-init` bootstrap depends on `depends_on` ordering, so it cannot work as
> written under Swarm. The `swarm/` stack solves all three.

---

## Quick Start

Each security configuration is located in its own directory under the `test/` folder. To get started:

1. Navigate to your desired configuration folder
2. Follow the specific setup guide for that configuration
3. Use `docker compose up -d` to start the stack
4. Access Kafka UI at `http://localhost:8080`

For the Swarm deployment instead, see [`swarm/SWARM_SETUP_GUIDE.md`](swarm/SWARM_SETUP_GUIDE.md).

---

## Available Security Configurations

### 1. **SASL/PLAIN (Baseline - No Encryption)**
- **Location**: `test/kafka-no-zookeeper-sassl/`
- **Security Protocol**: `SASL_PLAINTEXT`
- **Authentication**: SASL/PLAIN username/password
- **Encryption**: None (plaintext traffic on the wire)
- **Use Case**: Development, testing in isolated networks
- **Complexity**: ⭐ Minimal (no certificate generation needed)

### 2. **SASL + SSL/TLS**
- **Location**: `test/kafka-no-zookeeper-sasl-ssl/`
- **Security Protocol**: `SASL_SSL`
- **Authentication**: SASL/PLAIN username/password
- **Encryption**: TLS (one-way certificate verification)
- **Client Certificates**: Not required (broker certificate only)
- **Use Case**: Production with password-based authentication
- **Complexity**: ⭐⭐ (requires certificate generation)

### 3. **Mutual TLS (mTLS) Only**
- **Location**: `test/kafka-no-zookeeper-ssl-mtls/`
- **Security Protocol**: `SSL`
- **Authentication**: Client certificate-based (no passwords)
- **Encryption**: TLS (mutual certificate verification)
- **Client Certificates**: **Required** (both broker and client)
- **Use Case**: High-security, certificate-based authentication
- **Complexity**: ⭐⭐ (requires certificate generation)

### 4. **SASL/PLAIN + Mutual TLS (mTLS)**
- **Location**: `test/kafka-no-zookeeper-sasl-mtls/`
- **Security Protocol**: `SASL_SSL` with mutual TLS
- **Authentication**: SASL/PLAIN username/password + client certificates
- **Encryption**: TLS (mutual certificate verification)
- **Client Certificates**: **Required** (on top of SASL)
- **Use Case**: Maximum security with dual authentication layers
- **Complexity**: ⭐⭐⭐ (requires certificate generation + SASL users)

### 5. **SASL/SCRAM-SHA-256 + Mutual TLS (mTLS)**
- **Location**: `test/kafka-no-zookeeper-sasl-scram-mtls/`
- **Security Protocol**: `SASL_SSL` with mutual TLS
- **Authentication**: SASL/SCRAM-SHA-256 (salted password hashing) + client certificates
- **Encryption**: TLS (mutual certificate verification)
- **Client Certificates**: **Required**
- **Credential Storage**: Stored in cluster metadata (not static JAAS files)
- **Use Case**: Enterprise environments requiring stronger password hashing
- **Complexity**: ⭐⭐⭐ (requires certificate generation + metadata-based user management)

---

## Setup Guides

### Prerequisites (All Configurations)

- **Docker** and **Docker Compose** installed
- **OpenSSL** (for certificate generation on mTLS setups)
  - On Windows: Available in Git Bash or install separately
  - On Linux/Mac: Usually pre-installed
- **shared_network**: Must be created before running any stack

```bash
docker network create shared_network
```

---

## 1. SASL/PLAIN Setup (Easiest - No Encryption)

**Location**: `test/kafka-no-zookeeper-sassl/`

This is the baseline configuration with SASL/PLAIN authentication and no TLS encryption.

### Prerequisites

```bash
docker network create shared_network
```

### Start the Stack

```bash
docker compose -f test/kafka-no-zookeeper-sassl/docker-compose.yml up -d
```

Or navigate to the directory:

```bash
cd test/kafka-no-zookeeper-sassl
docker compose up -d
```

### Access Points

- **Broker (in-container)**: `kafka:9092`
- **Broker (localhost)**: `localhost:9094`
- **Kafka UI**: `http://localhost:8080`

### Standard Users Available

| username     | password       |
|--------------|----------------|
| admin        | admin-secret   |
| streamuser   | stream-secret  |

### Java Client Properties

```properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="streamuser";
```

### librdkafka / Confluent Clients

```
security.protocol=sasl_plaintext
sasl.mechanism=PLAIN
sasl.username=streamuser
```

### Bridge Service Configuration (`AppConfig.json`)

```json
{
  "BrokerUrl": "localhost:9094",
  "Security": {
    "Protocol": "SaslPlaintext",
    "Mechanism": "Plain",
    "SaslUsername": "streamuser",
    "SaslPassword": "stream-secret"
  }
}
```

**No SSL/TLS fields needed** — there's no encryption in this example.

### Verification

This stack has been verified to work end-to-end: broker starts cleanly, kafka-ui connects and reports the cluster `ONLINE`, and the bridge service has successfully connected to it.

---

## 2. SASL + SSL/TLS Setup

**Location**: `test/kafka-no-zookeeper-sasl-ssl/`

Single-broker KRaft Kafka with SASL/PLAIN authentication and TLS encryption. Clients only need the CA cert, not their own certificate.

### Prerequisites

```bash
docker network create shared_network
```

Requires `openssl` and `docker`.

### Generate Certificates

All certificates are written to `./secrets/` directory with default password: `changeit`

**Using Git Bash or Linux shell**:

```bash
cd test/kafka-no-zookeeper-sasl-ssl
./generate-certs.sh
```

**Using native PowerShell** (no Git Bash needed):

```powershell
cd test/kafka-no-zookeeper-sasl-ssl
.\generate-certs.ps1
```

If PowerShell blocks the script:

```powershell
powershell -ExecutionPolicy Bypass -File .\generate-certs.ps1
```

**Override certificate password** (default `changeit`):

```bash
CERT_PASSWORD=mypassword ./generate-certs.sh
```

### Generated Certificates

| File | Purpose |
|------|---------|
| `ca.crt` / `ca.key` | The example CA. `ca.crt` is what clients use to verify the broker. |
| `kafka.keystore.p12` | Broker private key + certificate bundle (PKCS12) |
| `kafka.truststore.p12` | Trusted CA certificates (PKCS12) |
| `kafka_keystore_creds` | Broker keystore password file |
| `kafka_truststore_creds` | Broker truststore password file |

### Start the Stack

```bash
cd test/kafka-no-zookeeper-sasl-ssl
docker compose up -d
```

### Access Points

- **Broker (in-container)**: `kafka:9092`
- **Broker (localhost)**: `localhost:9094`
- **Kafka UI**: `http://localhost:8080`

### Standard Users Available

| username     | password       |
|--------------|----------------|
| admin        | admin-secret   |
| streamuser   | stream-secret  |

### Java Client Properties

```properties
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="streamuser";
ssl.truststore.location=<path>/kafka.truststore.p12
ssl.truststore.type=PKCS12
```

### librdkafka / Confluent Clients (PEM)

```
security.protocol=sasl_ssl
sasl.mechanism=PLAIN
sasl.username=streamuser
ssl.ca.location=<path>/ca.crt
```

### Bridge Service Configuration (`AppConfig.json`)

```json
{
  "BrokerUrl": "localhost:9094",
  "Security": {
    "Protocol": "SaslSsl",
    "Mechanism": "Plain",
    "SaslUsername": "streamuser",
    "SaslPassword": "stream-secret",
    "SslCaLocation": "C:/path/to/ca.crt"
  }
}
```

**Note**: No client certificate needed — only the CA cert for server verification.

### Hostname Verification

The broker cert's SAN includes both `kafka` and `localhost`, so hostname verification works whether you connect from inside the docker network (`kafka:9092`) or from the host (`localhost:9094`).

### Verification

This stack has been verified to work end-to-end: broker starts cleanly on both SASL_SSL listeners, and kafka-ui connects and reports the cluster `ONLINE`.

---

## 3. Mutual TLS (mTLS) Only Setup

**Location**: `test/kafka-no-zookeeper-ssl-mtls/`

Single-broker KRaft Kafka with certificate-based authentication (no passwords). Every client must present its own certificate signed by the CA.

### Prerequisites

```bash
docker network create shared_network
```

Requires `openssl` and `docker`.

### Generate Certificates

**Using Git Bash or Linux shell**:

```bash
cd test/kafka-no-zookeeper-ssl-mtls
./generate-certs.sh
```

**Using native PowerShell**:

```powershell
cd test/kafka-no-zookeeper-ssl-mtls
.\generate-certs.ps1
```

If PowerShell blocks the script:

```powershell
powershell -ExecutionPolicy Bypass -File .\generate-certs.ps1
```

### Generated Certificates

| File | Purpose |
|------|---------|
| `ca.crt` / `ca.key` | The example CA. `ca.crt` is what clients use to verify the broker. |
| `kafka.keystore.p12` | Broker private key + certificate bundle (PKCS12) |
| `kafka.truststore.p12` | Trusted CA certificates (PKCS12) |
| `kafka_keystore_creds` | Broker keystore password file |
| `kafka_truststore_creds` | Broker truststore password file |
| `kafka-ui.keystore.p12` | Client certificate for kafka-ui (Java, PKCS12) |
| `client.crt` / `client.key` | Client certificate for librdkafka clients (e.g. bridge service), in PEM format |

### Adding New Client Certificates

To issue a certificate for an additional client, re-use the `make_client_cert()` function in the generate-certs script with a new name. Any cert signed by `ca.crt` with the `clientAuth` Extended Key Usage (EKU) is accepted by the broker.

### Start the Stack

```bash
cd test/kafka-no-zookeeper-ssl-mtls
docker compose up -d
```

### Access Points

- **Broker (in-container)**: `kafka:9092`
- **Broker (localhost)**: `localhost:9094`
- **Kafka UI**: `http://localhost:8080`

### Java Client Properties

```properties
security.protocol=SSL
ssl.truststore.location=<path>/kafka.truststore.p12
ssl.truststore.type=PKCS12
ssl.keystore.location=<path>/<client>.keystore.p12
ssl.keystore.type=PKCS12
```

### librdkafka / Confluent Clients (PEM)

```
security.protocol=ssl
ssl.ca.location=<path>/ca.crt
ssl.certificate.location=<path>/client.crt
ssl.key.location=<path>/client.key
```

### Bridge Service Configuration (`AppConfig.json`)

```json
{
  "BrokerUrl": "localhost:9094",
  "Security": {
    "Protocol": "Ssl",
    "SslCaLocation": "C:/path/to/ca.crt",
    "SslCertificateLocation": "C:/path/to/client.crt",
    "SslKeyLocation": "C:/path/to/client.key"
  }
}
```

**Note**: No SASL username/password — authentication is done entirely via certificates.

### Hostname Verification

The broker cert's SAN covers both `kafka` and `localhost`, so hostname verification works from inside the docker network and from the host.

### Important Notes

- `ssl.client.auth=required`: Every client **must** present its own certificate signed by the example CA, or the TLS handshake fails.
- The client's identity (principal) is the certificate's subject, e.g. `CN=client`.
- The controller listener stays `PLAINTEXT` (single node, intra-cluster only).

---

## 4. SASL/PLAIN + Mutual TLS (mTLS) Setup

**Location**: `test/kafka-no-zookeeper-sasl-mtls/`

Single-broker KRaft Kafka combining SASL/PLAIN authentication and mutual TLS. Both authentication layers must pass — the session principal comes from SASL (the cert DN is not used for identity).

### Prerequisites

```bash
docker network create shared_network
```

Requires `openssl` and `docker`.

### Generate Certificates

**Using Git Bash or Linux shell**:

```bash
cd test/kafka-no-zookeeper-sasl-mtls
./generate-certs.sh
```

**Using native PowerShell**:

```powershell
cd test/kafka-no-zookeeper-sasl-mtls
.\generate-certs.ps1
```

If PowerShell blocks the script:

```powershell
powershell -ExecutionPolicy Bypass -File .\generate-certs.ps1
```

### Generated Certificates

| File | Purpose |
|------|---------|
| `ca.crt` / `ca.key` | The example CA. `ca.crt` is what clients use to verify the broker. |
| `kafka.keystore.p12` | Broker keystore + password files for the apache/kafka image |
| `kafka.truststore.p12` | Broker truststore + password files for the apache/kafka image |
| `kafka-ui.keystore.p12` | Client certificate for kafka-ui (Java, PKCS12) |
| `client.crt` / `client.key` | Client certificate for librdkafka-based clients (e.g. bridge service), in PEM format. `client.key` has no passphrase. |

### Start the Stack

```bash
cd test/kafka-no-zookeeper-sasl-mtls
docker compose up -d
```

### Access Points

- **Broker (in-container)**: `kafka:9092`
- **Broker (localhost)**: `localhost:9094`
- **Kafka UI**: `http://localhost:8080`

### Standard Users Available

| username     | password       |
|--------------|----------------|
| admin        | admin-secret   |
| streamuser   | stream-secret  |

### Java Client Properties

```properties
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="streamuser";
ssl.truststore.location=<path>/kafka.truststore.p12
ssl.truststore.type=PKCS12
ssl.keystore.location=<path>/<client>.keystore.p12
ssl.keystore.type=PKCS12
```

### librdkafka / Confluent Clients (PEM)

```
security.protocol=sasl_ssl
sasl.mechanism=PLAIN
sasl.username=streamuser
ssl.ca.location=<path>/ca.crt
ssl.certificate.location=<path>/client.crt
ssl.key.location=<path>/client.key
```

### Bridge Service Configuration (`AppConfig.json`)

```json
{
  "BrokerUrl": "localhost:9094",
  "Security": {
    "Protocol": "SaslSsl",
    "Mechanism": "Plain",
    "SaslUsername": "streamuser",
    "SaslPassword": "stream-secret",
    "SslCaLocation": "C:/path/to/ca.crt",
    "SslCertificateLocation": "C:/path/to/client.crt",
    "SslKeyLocation": "C:/path/to/client.key"
  }
}
```

### Important Notes

- **Dual authentication**: Both SASL/PLAIN and mTLS must pass for connection to succeed.
- `ssl.client.auth=required`: Every client must present its own certificate on top of providing SASL credentials.
- The session principal comes from SASL (the cert DN is not used for identity).
- The controller listener stays `PLAINTEXT` (single node, intra-cluster only).
- Hostname verification works from both inside the docker network and from the host.

---

## 5. SASL/SCRAM-SHA-256 + Mutual TLS (mTLS) Setup

**Location**: `test/kafka-no-zookeeper-sasl-scram-mtls/`

Single-broker KRaft Kafka combining SASL/SCRAM-SHA-256 (stronger password hashing) and mutual TLS. Unlike SASL/PLAIN, SCRAM credentials aren't stored in static JAAS files—they live in the cluster's metadata.

### Prerequisites

```bash
docker network create shared_network
```

Requires `openssl` and `docker`.

### Generate Certificates

**Using Git Bash or Linux shell**:

```bash
cd test/kafka-no-zookeeper-sasl-scram-mtls
./generate-certs.sh
```

**Using native PowerShell**:

```powershell
cd test/kafka-no-zookeeper-sasl-scram-mtls
.\generate-certs.ps1
```

If PowerShell blocks the script:

```powershell
powershell -ExecutionPolicy Bypass -File .\generate-certs.ps1
```

### Generated Certificates

| File | Purpose |
|------|---------|
| `ca.crt` / `ca.key` | The example CA |
| `kafka.keystore.p12` | Broker keystore + password files |
| `kafka.truststore.p12` | Broker truststore + password files |
| `kafka-ui.keystore.p12` | Client certificate for kafka-ui |
| `client.crt` / `client.key` | Client certificate for librdkafka clients, PEM format, no passphrase |

### How SCRAM Bootstrap Works

Unlike SASL/PLAIN, SCRAM credentials live in the cluster's metadata, normally added via an already-authenticated admin connection (`kafka-configs.sh --alter --add-config ...`). But every listener here requires SASL+mTLS from the very first boot, so there's no unauthenticated path to create that first user.

**Solution**: A one-shot `kafka-init` service runs before the broker starts and bakes both users' SCRAM credentials directly into the KRaft metadata log at format time:

```bash
kafka-storage.sh format --cluster-id local --config /tmp/format.properties \
  --add-scram 'SCRAM-SHA-256=[name=admin,password=admin-secret]' \
  --add-scram 'SCRAM-SHA-256=[name=streamuser,password=stream-secret]'
```

The `kafka-init` service shares the `kafka-scram-data` volume with the `kafka` service, so when the broker's own startup formatting runs, it finds storage already formatted and skips re-formatting. The `kafka` service is set to `depends_on: kafka-init: condition: service_completed_successfully`, ensuring initialization always runs first.

> **This approach is Compose-only — it cannot work under Docker Swarm.**
> `docker stack deploy` ignores `depends_on`, so the ordering guarantee
> disappears, and the shared named volume would additionally require both
> containers pinned to the same node. The [`swarm/`](swarm/) stack avoids the
> problem entirely by keeping a PLAINTEXT listener available, which leaves an
> unauthenticated path in to create the first SCRAM user with a plain
> `kafka-configs.sh` call — see `swarm/create-scram-users.sh`.

### Start the Stack

```bash
cd test/kafka-no-zookeeper-sasl-scram-mtls
docker compose up -d
```

### Check Bootstrap Progress

```bash
docker compose logs kafka-init
```

### Access Points

- **Broker (in-container)**: `kafka:9092`
- **Broker (localhost)**: `localhost:9094`
- **Kafka UI**: `http://localhost:8080`

### Standard Users Available

| username     | password       |
|--------------|----------------|
| admin        | admin-secret   |
| streamuser   | stream-secret  |

### Reset Cluster (to start fresh or add new SCRAM users)

```bash
docker compose down
docker volume rm kafka-no-zookeeper-sasl-scram-mtls_kafka-scram-data
docker compose up -d
```

This removes the persisted metadata volume, forcing `kafka-init` to reformat from scratch on next startup.

### Java Client Properties

```properties
security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-256
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="streamuser";
ssl.truststore.location=<path>/kafka.truststore.p12
ssl.truststore.type=PKCS12
ssl.keystore.location=<path>/<client>.keystore.p12
ssl.keystore.type=PKCS12
```

### librdkafka / Confluent Clients (PEM)

```
security.protocol=sasl_ssl
sasl.mechanism=SCRAM-SHA-256
sasl.username=streamuser
ssl.ca.location=<path>/ca.crt
ssl.certificate.location=<path>/client.crt
ssl.key.location=<path>/client.key
```

### Bridge Service Configuration (`AppConfig.json`)

```json
{
  "BrokerUrl": "localhost:9094",
  "Security": {
    "Protocol": "SaslSsl",
    "Mechanism": "ScramSha256",
    "SaslUsername": "streamuser",
    "SaslPassword": "stream-secret",
    "SslCaLocation": "C:/path/to/ca.crt",
    "SslCertificateLocation": "C:/path/to/client.crt",
    "SslKeyLocation": "C:/path/to/client.key"
  }
}
```

### Verification

This stack has been verified to work end-to-end:
- Broker starts cleanly
- kafka-ui connects over SASL/SCRAM-SHA-256 + mTLS
- Cluster reports `ONLINE`

### Important Implementation Notes

If you modify `format.properties` or `docker-compose.yml`, be aware:

1. **Complete listener setup required**: `kafka-storage.sh format` builds a full broker config internally to validate before writing metadata, so `format.properties` needs the complete listener setup (`controller.listener.names`, `listeners`, `listener.security.protocol.map`, `inter.broker.listener.name`).

2. **Volume ownership**: The named volume's log directory doesn't pre-exist in the image, so Docker creates it root-owned on first mount. `kafka-init` runs as root (`user: "0:0"`) and `chown`s the directory to uid 1000 afterward, so the `kafka` service (which runs as the image's default non-root `appuser`) can still write to it.

---

## Docker Swarm deployment

**Location**: [`swarm/`](swarm/) — full walkthrough in
[`swarm/SWARM_SETUP_GUIDE.md`](swarm/SWARM_SETUP_GUIDE.md).

For the two-node Swarm (Kafka on `role=kafka`, application services on
`role=bridge`), a single Kafka stack exposes **every** security posture at once,
each on its own port. Deploy the broker once; switch scenario by changing only
the client configuration.

### Port map

| Port | Listener | Protocol | Mechanism | Client cert | Scenario |
|---|---|---|---|---|---|
| 9092 | `PLAINTEXT` | PLAINTEXT | — | — | **existing / production + inter-broker** |
| 9093 | `CONTROLLER` | PLAINTEXT | — | — | KRaft internal |
| 9094 | `PLAINTEXT_HOST` | PLAINTEXT | — | — | **existing** external |
| 9095 | `SASLPLAIN` | SASL_PLAINTEXT | PLAIN | no | 1 |
| 9096 | `SASLSSL` | SASL_SSL | PLAIN | no | **2 — start here** |
| 9097 | `MTLS` | SSL | — | required | 3 |
| 9098 | `SASLMTLS` | SASL_SSL | PLAIN | required | 4 |
| 9099 | `SCRAMMTLS` | SASL_SSL | SCRAM-SHA-256 | required | 5 |

Ports 9092/9093/9094 are byte-for-byte unchanged from the existing production
stack, so Bridge Service, VPS, Gateway and kafka-ui keep working throughout.
Ports 9095–9099 are in-swarm only — no new host ports or firewall rules.

### Files

| File | Purpose |
|---|---|
| `docker-compose.kafka-secure.yml` | Kafka stack, all listeners. Drop-in for the existing Kafka stack. |
| `docker-compose.bridge-secure.yml` | Bridge stack — all three Kafka clients with a `Security` block. |
| `generate-certs.sh` / `.ps1` | CA, broker keystore/truststore, client certs. SAN includes the Kafka node IP. |
| `create-scram-users.sh` | SCRAM credentials (scenario 5 only). |
| `kafka_server_jaas.conf` | Broker JAAS entry required by the SCRAM listener. |
| `docker-compose.local-preflight.yml` | Same broker config for plain `docker compose` on a laptop. |

### Three clients, not one

`bridge-service`, `virtual-parameter-service` **and** `gateway-service` all
connect to Kafka. Securing the broker and updating only the Bridge Service
breaks the other two. All three are configured in
`docker-compose.bridge-secure.yml`.

Environment-variable form maps 1:1 onto the JSON, double underscore per level:

```yaml
StreamApiConfig__BrokerUrl: "kafka:9096"
StreamApiConfig__Security__Protocol: "SaslSsl"
StreamApiConfig__Security__Mechanism: "Plain"
StreamApiConfig__Security__SaslUsername: "streamuser"
StreamApiConfig__Security__SaslPassword: "stream-secret"
StreamApiConfig__Security__SslCaLocation: "/etc/kafka/secrets/ca.crt"
```

### Verification status

The broker configuration in `docker-compose.kafka-secure.yml` was validated
end-to-end on single-node Docker before being committed: all seven listeners
bound, `Kafka Server started` clean, SCRAM users created over the plaintext
listener, and a SASL_SSL create-topic/list round-trip succeeded. Two defects
were found and fixed during that check — both documented under
[Troubleshooting](#troubleshooting).

Not yet run on the Swarm itself.

---

## Certificate Generation Details

### Generated Files (mTLS Configurations)

When you run `generate-certs.sh` or `generate-certs.ps1`, the following files are created in `./secrets/`:

| File | Purpose | Used By |
|------|---------|---------|
| `ca.crt` / `ca.key` | Certificate Authority (root CA) | Clients verify broker; broker verifies clients |
| `kafka.keystore.p12` | Broker private key + certificate bundle (PKCS12) | Kafka broker |
| `kafka.truststore.p12` | Trusted CA certificates (PKCS12) | Kafka broker (client verification) |
| `kafka_keystore_creds` | Keystore password file | Docker environment |
| `kafka_truststore_creds` | Truststore password file | Docker environment |
| `kafka-ui.keystore.p12` | Kafka UI client certificate (PKCS12) | Kafka UI (Java client) |
| `client.crt` | Client certificate (PEM) | librdkafka clients, bridge service |
| `client.key` | Client private key (PEM, no passphrase) | librdkafka clients, bridge service |

### Adding New Client Certificates

To issue a certificate for an additional client:

1. Re-use the `make_client_cert()` function from `generate-certs.sh` with a new name
2. Any certificate signed by `ca.crt` with the `clientAuth` Extended Key Usage (EKU) is accepted
3. Run the script again to generate new client certificates

---

## Client Connection Configuration Examples

### Java Client (SASL/PLAIN + SSL/TLS)

```properties
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="streamuser";
ssl.truststore.location=<path>/kafka.truststore.p12
ssl.truststore.type=PKCS12
```

### Java Client (SASL/SCRAM-SHA-256 + mTLS)

```properties
security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-256
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="streamuser";
ssl.truststore.location=<path>/kafka.truststore.p12
ssl.truststore.type=PKCS12
ssl.keystore.location=<path>/client.keystore.p12
ssl.keystore.type=PKCS12
```

### librdkafka / Confluent Client (PEM Format)

```
security.protocol=sasl_ssl
sasl.mechanism=PLAIN
sasl.username=streamuser
ssl.ca.location=<path>/ca.crt
ssl.certificate.location=<path>/client.crt
ssl.key.location=<path>/client.key
```

### Bridge Service Configuration

Example `AppConfig.json` for the bridge service (SASL/PLAIN + mTLS):

```json
{
  "BrokerUrl": "localhost:9094",
  "Security": {
    "Protocol": "SaslSsl",
    "Mechanism": "Plain",
    "SslCaLocation": "C:/path/to/ca.crt",
    "SslCertificateLocation": "C:/path/to/client.crt",
    "SslKeyLocation": "C:/path/to/client.key"
  }
}
```

For mTLS-only (no SASL):

```json
{
  "BrokerUrl": "localhost:9094",
  "Security": {
    "Protocol": "Ssl",
    "SslCaLocation": "C:/path/to/ca.crt",
    "SslCertificateLocation": "C:/path/to/client.crt",
    "SslKeyLocation": "C:/path/to/client.key"
  }
}
```

---

## Common Management Tasks

### View Broker Logs

```bash
docker compose logs kafka
```

### View Bootstrap Progress (SCRAM Setup)

```bash
docker compose logs kafka-init
```

### Stop the Stack

```bash
docker compose down
```

### Stop Stack and Clean Volumes

```bash
docker compose down -v
```

### Reset SCRAM Credentials

```bash
docker compose down
docker volume rm kafka-no-zookeeper-sasl-scram-mtls_kafka-scram-data
docker compose up -d
```

---

## Directory Structure

```
Open-Streaming/
├── README.md (this file)
├── Local-Bridge/
│   ├── README.md
│   └── docker-compose-local-machine.yaml
├── swarm/                              <-- Docker Swarm, multi-node
│   ├── SWARM_SETUP_GUIDE.md
│   ├── docker-compose.kafka-secure.yml     (all 5 postures, one stack)
│   ├── docker-compose.bridge-secure.yml    (3 Kafka clients + Security)
│   ├── docker-compose.local-preflight.yml  (same broker, plain compose)
│   ├── generate-certs.sh / .ps1
│   ├── create-scram-users.sh
│   ├── kafka_server_jaas.conf
│   └── .gitignore                          (secrets/ never committed)
└── test/                               <-- single-node Compose
    ├── bridge service sample config/
    │   └── MSOConfigs_P/
    │       ├── AppConfig.json
    │       └── kafka-publisher-broker.yml
    ├── kafka-no-zookeeper-sassl/
    │   ├── README.md
    │   └── docker-compose.yml
    ├── kafka-no-zookeeper-sasl-ssl/
    │   ├── README.md
    │   ├── docker-compose.yml
    │   ├── generate-certs.sh
    │   └── generate-certs.ps1
    ├── kafka-no-zookeeper-ssl-mtls/
    │   ├── README.md
    │   ├── docker-compose.yml
    │   ├── generate-certs.sh
    │   └── generate-certs.ps1
    ├── kafka-no-zookeeper-sasl-mtls/
    │   ├── README.md
    │   ├── docker-compose.yml
    │   ├── generate-certs.sh
    │   └── generate-certs.ps1
    └── kafka-no-zookeeper-sasl-scram-mtls/
        ├── README.md
        ├── docker-compose.yml
        ├── generate-certs.sh
        └── generate-certs.ps1
```

---

## Security Comparison Matrix

| Configuration | SASL | SCRAM | mTLS | Passwords | Certs | Complexity |
|---|---|---|---|---|---|---|
| **SASL/PLAIN** | ✅ | ❌ | ❌ | ✅ | ❌ | Low |
| **SASL + SSL** | ✅ | ❌ | ❌ | ✅ | ✅ | Medium |
| **mTLS Only** | ❌ | ❌ | ✅ | ❌ | ✅ | Medium |
| **SASL + mTLS** | ✅ | ❌ | ✅ | ✅ | ✅ | High |
| **SASL/SCRAM + mTLS** | ✅ | ✅ | ✅ | ✅* | ✅ | High |

\* SCRAM credentials stored in cluster metadata, not plaintext

---

## Troubleshooting

### Issue: Broker fails to start

Check logs:
```bash
docker compose logs kafka
```

For SCRAM setup, also check:
```bash
docker compose logs kafka-init
```

### Issue: Certificate generation fails (Windows)

If using PowerShell and getting execution-policy errors:
```powershell
powershell -ExecutionPolicy Bypass -File .\generate-certs.ps1
```

Alternatively, use Git Bash or WSL.

**If instead the very first openssl command fails with something like:**
```
Can't open Z:/extlib/_5034__/ssl/openssl.cnf for reading, Invalid argument
```
the machine has more than one `openssl.exe` and PowerShell is picking the wrong
one — typically Strawberry Perl's, which is resolved ahead of Git's and looks
for a config file at a path baked in when it was compiled. Confirm with:

```powershell
Get-Command openssl -All
```

Fix by pointing at Git's config in the same session before running the script:

```powershell
$env:OPENSSL_CONF = "C:\Program Files\Git\mingw64\etc\ssl\openssl.cnf"
```

### Issue (Swarm): broker exits with `configure: line 18: !1: unbound variable`

The `apache/kafka` image's `/etc/kafka/docker/configure` detects `SSL://` in
`KAFKA_ADVERTISED_LISTENERS` and then hard-requires
`KAFKA_SSL_KEYSTORE_FILENAME`, `KAFKA_SSL_KEYSTORE_CREDENTIALS` and
`KAFKA_SSL_KEY_CREDENTIALS`. It runs under `set -u`, so supplying
`KAFKA_SSL_KEYSTORE_LOCATION` instead kills the container before Kafka starts.

Rule: **keystore must use the FILENAME/CREDENTIALS indirection; truststore must
be set directly** via `KAFKA_SSL_TRUSTSTORE_LOCATION`/`_PASSWORD`/`_TYPE` — the
same script only wires up truststore indirection when the *global*
`ssl.client.auth` is `required`/`requested`. Already handled in
`swarm/docker-compose.kafka-secure.yml`.

### Issue (Swarm): broker exits with `Could not find a 'KafkaServer' entry`

Full message: `Could not find a 'KafkaServer' or 'scrammtls.KafkaServer' entry
in the JAAS configuration.` Kafka requires a JAAS *entry* to exist for a
SCRAM-enabled listener even though the credentials themselves live in cluster
metadata. Supplied by `swarm/kafka_server_jaas.conf` plus the `KAFKA_OPTS` line
in the stack file — make sure that file was included when copying `secrets/`
to the Kafka node (`generate-certs.sh` copies it in automatically).

### Issue (Swarm): `secrets` directory empty inside the container

Swarm does not copy local files to remote nodes, so a relative `./secrets` bind
mount silently yields an empty directory. Stage the folder at an absolute path
**on the target node** and ensure it is owned by uid 1000 on the Kafka node.

### Issue: Port already in use

Only one stack can run at a time (all use ports 9094 and 8080).

Stop running stacks:
```bash
docker compose down  # in the currently running config directory
```

### Issue: Kafka UI cannot connect

- Verify broker is running: `docker compose logs kafka`
- Check if using mTLS: Kafka UI needs `kafka-ui.keystore.p12` in the broker container
- Verify network: `docker network ls`

---

## Additional Resources

- Individual README files in each configuration directory for detailed setup notes
- Bridge service example configuration in `test/bridge service sample config/`
- Docker Compose configurations reference the `shared_network` for inter-container communication

---

## Notes

- **Single-broker setup**: All configurations use a single KRaft broker (no ZooKeeper)
- **Shared network**: All stacks require the `shared_network` Docker network
- **Port mapping**: Broker uses 9094 (external) / 9092 (internal), Kafka UI uses 8080
- **One stack at a time**: Configuration ports don't overlap, but container names do—only run one stack
- **Hostname verification**: Broker certificates include SANs for both `kafka` and `localhost`

For detailed information about each setup, refer to the individual README files in each configuration folder.
