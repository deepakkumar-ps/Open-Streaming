# Kafka (KRaft, no ZooKeeper) with SASL/PLAIN

Single-broker KRaft Kafka example — the baseline this repo's other examples
build on:

- Client and inter-broker listeners use `SASL_PLAINTEXT`: SASL/PLAIN
  authentication, no encryption (traffic is plaintext on the wire).
- No certificates, no TLS setup — just the JAAS config for SASL.
- The controller listener stays `PLAINTEXT` (single-node, intra-cluster only).

## 1. Create the shared network (if it doesn't already exist)

```bash
docker network create shared_network
```

## 2. Start the stack

Note: this uses the same container names and host ports (9094, 8080) as the
other examples — only one of the stacks can run at a time.

```bash
docker compose up -d
```

- Broker (in-network): `kafka:9092`
- Broker (host): `localhost:9094`
- Kafka UI: http://localhost:8080

## Credentials

Same users as the other SASL examples in this repo:

| username     | password       |
|--------------|----------------|
| admin        | admin-secret   |
| streamuser   | stream-secret  |

## Client connection settings

Java client properties:

```
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="streamuser" password="stream-secret";
```

librdkafka / Confluent clients:

```
security.protocol=sasl_plaintext
sasl.mechanism=PLAIN
sasl.username=streamuser
sasl.password=stream-secret
```

### Bridge service (`AppConfig.json`)

```json
"BrokerUrl": "localhost:9094",
"Security": {
  "SaslUsername": "streamuser",
  "SaslPassword": "stream-secret",
  "Protocol": "SaslPlaintext",
  "Mechanism": "Plain"
}
```

No `Ssl*` fields — there's no TLS in this example, so no CA cert or client
certificate is needed.

## Verified

This stack has been run repeatedly end-to-end during development of the other
examples: broker starts cleanly, kafka-ui connects and reports the cluster
`ONLINE`, and the bridge service has connected to it successfully.
