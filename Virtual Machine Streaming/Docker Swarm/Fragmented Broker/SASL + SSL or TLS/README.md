# Kafka (KRaft, no ZooKeeper) with SASL + SSL

Single-broker KRaft Kafka example, same shape as `kafka-no-zookeeper-auth`, but
the client and inter-broker listeners use `SASL_SSL`:

- SASL/PLAIN for authentication, TLS for encryption.
- `ssl.client.auth=none` — clients don't need their own certificate, only the
  CA cert to verify the broker. Authentication is entirely via SASL username/password.
- The controller listener stays `PLAINTEXT` (single-node, intra-cluster only).

## 1. Generate certificates

Requires `openssl` (Git Bash on Windows) and `docker` (docker is used to run
`keytool` from the apache/kafka image itself, so no host JDK is needed).

```bash
./generate-certs.sh
```

Or, on native PowerShell (no Git Bash needed, just `openssl` and `docker` on
`PATH`):

```powershell
.\generate-certs.ps1
```

(If PowerShell blocks the script with an execution-policy error, run
`powershell -ExecutionPolicy Bypass -File .\generate-certs.ps1` instead.)

Everything is written to `./secrets/` (password for all stores: `changeit`,
override with `CERT_PASSWORD=... ./generate-certs.sh`):

| File | Purpose |
|------|---------|
| `ca.crt` / `ca.key` | The example CA. `ca.crt` is what clients use to verify the broker. |
| `kafka.keystore.p12`, `kafka.truststore.p12`, `kafka_*_creds` | Broker keystore/truststore + password files for the apache/kafka image. |

PKCS12 is used (instead of PEM) because the apache/kafka image's configure
script requires a keystore filename + credentials-file pair
(`KAFKA_SSL_KEYSTORE_FILENAME` / `KAFKA_SSL_KEYSTORE_CREDENTIALS` /
`KAFKA_SSL_KEY_CREDENTIALS`), and PKCS12 can be built with plain `openssl`.

Re-run the script any time to regenerate fresh certs.

## 2. Create the shared network (if it doesn't already exist)

```bash
docker network create shared_network
```

## 3. Start the stack

Note: this uses the same container names and host ports (9094, 8080) as the
other examples — only one of the stacks can run at a time.

```bash
docker compose up -d
```

- Broker (in-network): `kafka:9092`
- Broker (host): `localhost:9094`
- Kafka UI: http://localhost:8080

## Credentials

Same users as `kafka-no-zookeeper-sassl`:

| username     | password       |
|--------------|----------------|
| admin        | admin-secret   |
| streamuser   | stream-secret  |

## Client connection settings

A client needs SASL credentials and the CA cert (no client certificate needed).

Java client properties:

```
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="streamuser" password="stream-secret";
ssl.truststore.location=<path>/kafka.truststore.p12
ssl.truststore.type=PKCS12
ssl.truststore.password=changeit
```

librdkafka / Confluent clients (PEM):

```
security.protocol=sasl_ssl
sasl.mechanism=PLAIN
sasl.username=streamuser
sasl.password=stream-secret
ssl.ca.location=<path>/ca.crt
```

### Bridge service (`AppConfig.json`)

```json
"BrokerUrl": "localhost:9094",
"Security": {
  "Protocol": "SaslSsl",
  "Mechanism": "Plain",
  "SaslUsername": "streamuser",
  "SaslPassword": "stream-secret",
  "SslCaLocation": "C:/Builds/Kafka with authentication/kafka-no-zookeeper-sasl-ssl/secrets/ca.crt"
}
```

(No `SslCertificateLocation`/`SslKeyLocation` — the broker doesn't require a
client certificate.)

Since the broker cert's SAN includes both `kafka` and `localhost`, hostname
verification works whether you connect from another container (`kafka:9092`)
or from the host (`localhost:9094`) — no need to disable
`ssl.endpoint.identification.algorithm`.

## Verified

This stack has been run end-to-end: broker starts cleanly on both SASL_SSL
listeners, and kafka-ui connects and reports the cluster `ONLINE`.
