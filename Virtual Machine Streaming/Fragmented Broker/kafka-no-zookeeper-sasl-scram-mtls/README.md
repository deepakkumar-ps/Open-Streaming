# Kafka (KRaft, no ZooKeeper) with SASL/SCRAM-SHA-256 + mutual TLS (mTLS)

Same combined-security shape as `kafka-no-zookeeper-sasl-mtls`, but the SASL
mechanism is `SCRAM-SHA-256` instead of `PLAIN`:

- Listeners use `SASL_SSL`: TLS encryption + SASL/SCRAM-SHA-256 authentication.
- `ssl.client.auth=required`: every client must also present its own
  certificate signed by the example CA, on top of SASL.
- The controller listener stays `PLAINTEXT` (single node, intra-cluster only).

## Why this one needs an extra step

Unlike `PLAIN`, SCRAM credentials aren't stored in a static JAAS file — they
live in the cluster's metadata, normally added via an already-authenticated
admin connection (`kafka-configs.sh --alter --add-config ...`). But every
listener here requires SASL+mTLS from the very first boot, so there's no
unauthenticated path to create that first user (the classic KRaft SCRAM
bootstrap problem).

`docker-compose.yml` solves this with a one-shot `kafka-init` service that
runs before the broker starts:

```
kafka-storage.sh format --cluster-id local --config /tmp/format.properties \
  --add-scram 'SCRAM-SHA-256=[name=admin,password=admin-secret]' \
  --add-scram 'SCRAM-SHA-256=[name=streamuser,password=stream-secret]'
```

This bakes both users' SCRAM credentials directly into the KRaft metadata log
at format time. It shares the `kafka-scram-data` volume with the `kafka`
service, so when the broker's own startup formatting runs, it finds storage
already formatted and skips re-formatting — the `kafka` service is set to
`depends_on: kafka-init: condition: service_completed_successfully` so this
always runs first.

If you ever want to reset (e.g. to add another SCRAM user), remove the
volume so `kafka-init` reformats from scratch:

```bash
docker compose down
docker volume rm kafka-no-zookeeper-sasl-scram-mtls_kafka-scram-data
```

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

Same output as the other mTLS examples, written to `./secrets/` (password
`changeit`, override with `CERT_PASSWORD=...`):

| File | Purpose |
|------|---------|
| `ca.crt` / `ca.key` | The example CA. |
| `kafka.keystore.p12`, `kafka.truststore.p12`, `kafka_*_creds` | Broker keystore/truststore + password files. |
| `kafka-ui.keystore.p12` | Client certificate for kafka-ui. |
| `client.crt` / `client.key` | Client certificate for librdkafka clients (e.g. the bridge service), PEM, no passphrase. |

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

Check `docker compose logs kafka-init` first if the broker doesn't come up —
that's where the SCRAM bootstrap step's output goes.

- Broker (in-network): `kafka:9092`
- Broker (host): `localhost:9094`
- Kafka UI: http://localhost:8080

## Credentials

| username     | password       |
|--------------|----------------|
| admin        | admin-secret   |
| streamuser   | stream-secret  |

## Client connection settings

Java client properties:

```
security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-256
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="streamuser" password="stream-secret";
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
sasl.mechanism=SCRAM-SHA-256
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
  "Mechanism": "ScramSha256",
  "SaslUsername": "streamuser",
  "SaslPassword": "stream-secret",
  "SslCaLocation": "C:/Builds/Kafka with authentication/kafka-no-zookeeper-sasl-scram-mtls/secrets/ca.crt",
  "SslCertificateLocation": "C:/Builds/Kafka with authentication/kafka-no-zookeeper-sasl-scram-mtls/secrets/client.crt",
  "SslKeyLocation": "C:/Builds/Kafka with authentication/kafka-no-zookeeper-sasl-scram-mtls/secrets/client.key"
}
```

## Verified

This stack has been run end-to-end (broker starts cleanly, kafka-ui connects
over SASL/SCRAM-SHA-256 + mTLS and reports the cluster `ONLINE`). Two
non-obvious things that had to be fixed to get there, worth knowing if you
touch `format.properties` or `docker-compose.yml`:

- `kafka-storage.sh format` builds a full broker config internally to
  validate before writing metadata, so `format.properties` needs the complete
  listener setup (`controller.listener.names`, `listeners`,
  `listener.security.protocol.map`, `inter.broker.listener.name`) — not just
  `log.dirs`.
- The named volume's log directory doesn't pre-exist in the image, so Docker
  creates it root-owned on first mount. `kafka-init` runs as root (`user:
  "0:0"`) and `chown`s the directory to uid 1000 afterward, so the `kafka`
  service (which runs as the image's default non-root `appuser`) can still
  write to it.
