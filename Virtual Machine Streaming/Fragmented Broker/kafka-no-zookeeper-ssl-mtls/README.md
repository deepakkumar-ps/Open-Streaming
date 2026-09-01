# Kafka (KRaft, no ZooKeeper) with mutual TLS (mTLS)

Single-broker KRaft Kafka example, same shape as the other examples in this
repo, but authentication is done purely with certificates:

- The `SSL` protocol is used on the client and inter-broker listeners
  (encryption via TLS, no SASL).
- `ssl.client.auth=required` — **every client must present its own certificate**
  signed by the example CA, or the TLS handshake is rejected. The client's
  identity (principal) is the certificate's subject, e.g. `CN=client`.
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
| `client.crt` / `client.key` | Client certificate for librdkafka-based clients (e.g. the bridge service), in PEM format. |

To issue a certificate for an additional client, re-use the `make_client_cert`
function in the script (or copy its four openssl commands) with a new name —
any cert signed by `ca.crt` with the `clientAuth` EKU is accepted by the broker.

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

## Client connection settings

There is no username/password. A client needs three things: the CA cert (to
trust the broker), plus its own certificate and private key (to authenticate).

Java client properties:

```
security.protocol=SSL
ssl.truststore.location=<path>/kafka.truststore.p12
ssl.truststore.type=PKCS12
ssl.truststore.password=changeit
ssl.keystore.location=<path>/<client>.keystore.p12
ssl.keystore.type=PKCS12
ssl.keystore.password=changeit
```

librdkafka / Confluent clients (PEM):

```
security.protocol=ssl
ssl.ca.location=<path>/ca.crt
ssl.certificate.location=<path>/client.crt
ssl.key.location=<path>/client.key
```

### Bridge service (`AppConfig.json`)

```json
"BrokerUrl": "localhost:9094",
"Security": {
  "Protocol": "Ssl",
  "SslCaLocation": "C:/Builds/Kafka with authentication/kafka-no-zookeeper-ssl-mtls/secrets/ca.crt",
  "SslCertificateLocation": "C:/Builds/Kafka with authentication/kafka-no-zookeeper-ssl-mtls/secrets/client.crt",
  "SslKeyLocation": "C:/Builds/Kafka with authentication/kafka-no-zookeeper-ssl-mtls/secrets/client.key"
}
```

(No `SaslUsername`/`SaslPassword`/`Mechanism` — authentication is the client
certificate itself.)

The broker cert's SAN covers both `kafka` and `localhost`, so hostname
verification works from inside the docker network and from the host.

## Note

This configuration hasn't been run end-to-end yet — only certificate
generation has been verified. If the broker or kafka-ui fails to start, check
`docker compose logs kafka` and `docker compose logs kafka-ui` first.
