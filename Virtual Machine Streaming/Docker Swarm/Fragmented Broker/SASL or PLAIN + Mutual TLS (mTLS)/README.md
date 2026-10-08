# Kafka (KRaft, no ZooKeeper) with SASL + mutual TLS (mTLS)

Single-broker KRaft Kafka example combining both authentication layers from the
other examples:

- Listeners use `SASL_SSL`: TLS encryption + SASL/PLAIN username/password.
- `ssl.client.auth=required`: on top of SASL, **every client must also present
  its own certificate** signed by the example CA or the TLS handshake fails.
- Both must pass. The session principal comes from SASL (the cert DN is not
  used for identity when SASL is in play).
- The controller listener stays `PLAINTEXT` (single node, intra-cluster only).

## 1. Generate certificates

Requires `openssl` (Git Bash on Windows) and `docker`.

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
| `kafka-ui.keystore.p12` | Client certificate for kafka-ui (Java, PKCS12). |
| `client.crt` / `client.key` | Client certificate for librdkafka-based clients (e.g. the bridge service), in PEM format. `client.key` has no passphrase. |

To issue a certificate for an additional client, re-use the `make_client_cert`
function in the script with a new name — any cert signed by `ca.crt` with the
`clientAuth` EKU is accepted by the broker.

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

Same SASL users as the other SASL examples:

| username     | password       |
|--------------|----------------|
| admin        | admin-secret   |
| streamuser   | stream-secret  |

## Client connection settings

A client needs SASL credentials **and** the CA cert **and** its own
certificate/key.

Java client properties:

```
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="streamuser" password="stream-secret";
ssl.truststore.location=<path>/kafka.truststore.p12
ssl.truststore.type=PKCS12
ssl.truststore.password=changeit
ssl.keystore.location=<path>/<client>.keystore.p12
ssl.keystore.type=PKCS12
ssl.keystore.password=changeit
```

librdkafka / Confluent clients (PEM):

```
security.protocol=sasl_ssl
sasl.mechanism=PLAIN
sasl.username=streamuser
sasl.password=stream-secret
ssl.ca.location=<path>/ca.crt
ssl.certificate.location=<path>/client.crt
ssl.key.location=<path>/client.key
```

### Bridge service (`AppConfig.json`)

```json
"BrokerUrl": "localhost:9094",
"Security": {
  "Protocol": "SaslSsl",
  "Mechanism": "Plain",
  "SaslUsername": "streamuser",
  "SaslPassword": "stream-secret",
  "SslCaLocation": "C:/Builds/Kafka with authentication/kafka-no-zookeeper-sasl-mtls/secrets/ca.crt",
  "SslCertificateLocation": "C:/Builds/Kafka with authentication/kafka-no-zookeeper-sasl-mtls/secrets/client.crt",
  "SslKeyLocation": "C:/Builds/Kafka with authentication/kafka-no-zookeeper-sasl-mtls/secrets/client.key"
}
```

(`SslKeyPassword` is not needed — `client.key` is unencrypted.)

The broker cert's SAN covers both `kafka` and `localhost`, so hostname
verification works from inside the docker network and from the host.

## Note

This configuration hasn't been run end-to-end yet — only certificate
generation has been verified. If the broker or kafka-ui fails to start, check
`docker compose logs kafka` and `docker compose logs kafka-ui` first.
