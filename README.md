# Open-Streaming

This repository includes comprehensive setup configurations for Kafka with various security authentication mechanisms. It provides Docker-based environments for testing different security protocols and integration examples.

## Table of Contents

- [Quick Start](#quick-start)
- [Available Security Configurations](#available-security-configurations)
- [Setup Guides](#setup-guides)
- [Directory Structure](#directory-structure)
- [Common Prerequisites](#common-prerequisites)

---

## Quick Start

Each security configuration is located in its own directory under the `test/` folder. To get started:

1. Navigate to your desired configuration folder
2. Follow the specific setup guide for that configuration
3. Use `docker compose up -d` to start the stack
4. Access Kafka UI at `http://localhost:8080`

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
└── test/
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
