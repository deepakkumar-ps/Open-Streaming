# Kafka Security — Docker Swarm Setup & Test Guide

Everything needed to test all five Kafka security postures against the existing
two-node Swarm, without disrupting the running unsecured setup.

**Design in one line:** one Kafka stack exposes every security posture on its own
port simultaneously, so you deploy the broker **once** and switch scenarios by
changing only the client config.

---

## Why one stack instead of five

| | Five separate stacks | One multi-listener stack (this) |
|---|---|---|
| Broker redeploys | 5, one per scenario | **1** |
| Production `PLAINTEXT:9092` | Torn down each time | **Untouched throughout** |
| Switching scenario | Redeploy Kafka + clients | Change client port + `Security` block |
| SCRAM bootstrap | Needs `kafka-init` + `depends_on` (**ignored by Swarm**) | Plain `kafka-configs.sh` over `:9092` |
| Risk if a config is wrong | One scenario broken | Broker down for all listeners |

The last row is the real trade-off. It's mitigated by the fact that the broker
config in `docker-compose.kafka-secure.yml` was **verified end-to-end on
single-node Docker before being written here**: all seven listeners bound, and
a SASL_SSL create-topic/list round-trip succeeded. Two bugs were found and fixed
during that check — see [Troubleshooting](#troubleshooting).

This also mirrors the real migration path: add listener → move clients one at a
time → retire plaintext.

---

## Port map

| Port | Listener | Protocol | Mechanism | Client cert | Scenario |
|---|---|---|---|---|---|
| 9092 | `PLAINTEXT` | PLAINTEXT | — | — | **existing / production + inter-broker** |
| 9093 | `CONTROLLER` | PLAINTEXT | — | — | KRaft internal |
| 9094 | `PLAINTEXT_HOST` | PLAINTEXT | — | — | **existing** external (`10.104.10.89`) |
| 9095 | `SASLPLAIN` | SASL_PLAINTEXT | PLAIN | no | 1 |
| 9096 | `SASLSSL` | SASL_SSL | PLAIN | no | **2 — start here** |
| 9097 | `MTLS` | SSL | — | **required** | 3 |
| 9098 | `SASLMTLS` | SASL_SSL | PLAIN | **required** | 4 |
| 9099 | `SCRAMMTLS` | SASL_SSL | SCRAM-SHA-256 | **required** | 5 |

9095–9099 are **in-swarm only** (`kafka:<port>`). Every client already runs on
the overlay network, so no new host ports or firewall rules are needed.

---

## Files

| File | Purpose |
|---|---|
| `generate-certs.sh` / `.ps1` | Creates CA, broker keystore/truststore, client certs. SAN includes `10.104.10.89`. |
| `docker-compose.kafka-secure.yml` | Swarm Kafka stack — all listeners. Drop-in for `docker-compose.kafka.yml`. |
| `docker-compose.bridge-secure.yml` | Swarm bridge stack — all 3 Kafka clients with a `Security` block. |
| `create-scram-users.sh` | Creates SCRAM credentials (only needed for scenario 5). |
| `secrets/kafka_server_jaas.conf` | Broker JAAS entry required by the SCRAM listener. |
| `docker-compose.local-preflight.yml` | Same broker config for plain `docker compose` on a laptop. Optional. |

---

## 1. Generate certificates (once)

Run anywhere with `openssl` + `docker` — a laptop is fine.

```bash
cd swarm
./generate-certs.sh
```

Windows PowerShell:

```powershell
$env:OPENSSL_CONF = "C:\Program Files\Git\mingw64\etc\ssl\openssl.cnf"
.\generate-certs.ps1
```

> The `OPENSSL_CONF` line is not optional if the machine has Strawberry Perl
> installed — PowerShell resolves its `openssl.exe` ahead of Git's, and that
> build looks for a config file at a path that doesn't exist, failing on the
> very first command. Check with `Get-Command openssl -All`.

Verify the SAN covers the Kafka node:

```bash
openssl x509 -in secrets/kafka.crt -noout -text | grep -A1 "Subject Alternative Name"
# DNS:kafka, DNS:localhost, IP Address:127.0.0.1, IP Address:10.104.10.89
```

If clients will reach Kafka by any other name or IP, add it before generating:

```bash
EXTRA_SANS="DNS:kafka.internal,IP:10.104.10.90" ./generate-certs.sh
```

Getting this wrong is the single most likely cause of a TLS failure that looks
like a broker fault. Never "fix" it by disabling hostname verification.

---

## 2. Stage certificates on both nodes

Swarm does **not** copy local files to remote nodes. A relative `./secrets`
bind mount would silently produce an empty directory inside the container.

**Kafka node** (needs everything, owned by uid 1000 — same as your data dir):

```bash
scp -r secrets ocsautotest@<kafka-node>:/home/ocsautotest/docker-composes/Kafka/
ssh ocsautotest@<kafka-node> \
  'sudo chown -R 1000:1000 /home/ocsautotest/docker-composes/Kafka/secrets'
```

**Bridge node** (only needs `ca.crt`, plus `client.crt`/`client.key` for mTLS
scenarios 3–5):

```bash
scp -r secrets ocsautotest@<bridge-node>:/home/ocsautotest/docker-composes/Bridge/
```

> `docker secret` is the tidier long-term answer. Bind mounts are used here
> because they match the pattern already in your Kafka stack, which keeps the
> number of new concepts at zero.

---

## 3. Deploy the Kafka stack

```bash
docker stack deploy -c docker-compose.kafka-secure.yml kafka
docker service logs -f kafka_kafka
```

Look for seven `Awaiting socket connections on 0.0.0.0:<port>` lines, then
`Kafka Server started`.

**Nothing has broken at this point.** `PLAINTEXT:9092` and `PLAINTEXT_HOST:9094`
are byte-for-byte what they were, so Bridge Service, VPS, Gateway and kafka-ui
keep running against the unsecured listener exactly as before. The five secured
listeners are simply sitting there unused.

Confirm via Kafka UI at `http://<kafka-node>:8080` — two clusters now appear:

- **local-plaintext** (`:9092`) — your existing view, should be Online
- **local-saslssl** (`:9096`) — proves scenario 2 works with zero application changes

If `local-saslssl` is Online, the TLS + SASL plumbing is correct before you
touch a single application service.

---

## 4. SCRAM users (only for scenario 5)

Run **on the Kafka node**, after the stack is up:

```bash
./create-scram-users.sh
```

This works because `:9092` is still unauthenticated, giving a path in to create
the first credentials. That is precisely the chicken-and-egg the old
`kafka-no-zookeeper-sasl-scram-mtls` scenario needed a `kafka-init` container
and `--add-scram`-at-format-time to work around — and that workaround relies on
`depends_on`, which `docker stack deploy` ignores. Keeping the plaintext
listener makes the whole problem disappear.

---

## 5. Switch a client to a secured listener

Edit `docker-compose.bridge-secure.yml` and redeploy:

```bash
docker stack deploy -c docker-compose.bridge-secure.yml bridge
```

It ships configured for **scenario 2**. To change scenario, set `BrokerUrl`
and the `Security__*` block on each of the three Kafka clients:

### Scenario 1 — SASL/PLAIN, no TLS
```yaml
StreamApiConfig__BrokerUrl: "kafka:9095"
StreamApiConfig__Security__Protocol: "SaslPlaintext"
StreamApiConfig__Security__Mechanism: "Plain"
StreamApiConfig__Security__SaslUsername: "streamuser"
StreamApiConfig__Security__SaslPassword: "stream-secret"
```

### Scenario 2 — SASL/PLAIN over TLS, no client cert *(default)*
```yaml
StreamApiConfig__BrokerUrl: "kafka:9096"
StreamApiConfig__Security__Protocol: "SaslSsl"
StreamApiConfig__Security__Mechanism: "Plain"
StreamApiConfig__Security__SaslUsername: "streamuser"
StreamApiConfig__Security__SaslPassword: "stream-secret"
StreamApiConfig__Security__SslCaLocation: "/etc/kafka/secrets/ca.crt"
```

### Scenario 3 — mTLS only, no SASL
```yaml
StreamApiConfig__BrokerUrl: "kafka:9097"
StreamApiConfig__Security__Protocol: "Ssl"
StreamApiConfig__Security__SslCaLocation: "/etc/kafka/secrets/ca.crt"
StreamApiConfig__Security__SslCertificateLocation: "/etc/kafka/secrets/client.crt"
StreamApiConfig__Security__SslKeyLocation: "/etc/kafka/secrets/client.key"
```

### Scenario 4 — SASL/PLAIN over TLS + client cert
```yaml
StreamApiConfig__BrokerUrl: "kafka:9098"
StreamApiConfig__Security__Protocol: "SaslSsl"
StreamApiConfig__Security__Mechanism: "Plain"
StreamApiConfig__Security__SaslUsername: "streamuser"
StreamApiConfig__Security__SaslPassword: "stream-secret"
StreamApiConfig__Security__SslCaLocation: "/etc/kafka/secrets/ca.crt"
StreamApiConfig__Security__SslCertificateLocation: "/etc/kafka/secrets/client.crt"
StreamApiConfig__Security__SslKeyLocation: "/etc/kafka/secrets/client.key"
```

### Scenario 5 — SASL/SCRAM-SHA-256 over TLS + client cert
```yaml
StreamApiConfig__BrokerUrl: "kafka:9099"
StreamApiConfig__Security__Protocol: "SaslSsl"
StreamApiConfig__Security__Mechanism: "ScramSha256"
StreamApiConfig__Security__SaslUsername: "streamuser"
StreamApiConfig__Security__SaslPassword: "stream-secret"
StreamApiConfig__Security__SslCaLocation: "/etc/kafka/secrets/ca.crt"
StreamApiConfig__Security__SslCertificateLocation: "/etc/kafka/secrets/client.crt"
StreamApiConfig__Security__SslKeyLocation: "/etc/kafka/secrets/client.key"
```

### Migrating one service at a time

For lowest risk, change **`gateway-service` first** (smallest blast radius),
then `virtual-parameter-service`, then `bridge-service`. Any service left on
`kafka:9092` keeps working — the listeners are independent.

---

## 6. Verify

```bash
docker service ls
docker service logs -f bridge_bridge-service | grep -iE "kafka|sasl|ssl|error"
```

Then in Kafka UI (`local-plaintext` cluster, since it sees the same data),
confirm topics under the `VitualTest.` prefix are still being written.

**A clean pass means:** the service starts without auth errors, topics keep
receiving data, and the broker log shows no `SSL handshake failed` /
`Authentication failed` entries.

### Negative tests — prove enforcement, not just acceptance

A connection succeeding only proves your config is right. These prove the
broker is actually enforcing:

| Test | Change | Expect |
|---|---|---|
| Wrong password | `SaslPassword: "wrong"` | SASL authentication failure |
| No security block | remove `Security__*`, keep secured port | Connection refused/handshake failure |
| Missing client cert (scenarios 3–5) | drop `SslCertificateLocation`/`SslKeyLocation` | TLS handshake rejected before SASL |
| Wrong CA | point `SslCaLocation` at an unrelated cert | Client-side trust failure |

---

## 7. Rollback

Instant, and needs no Kafka change:

```yaml
StreamApiConfig__BrokerUrl: "kafka:9092"
# delete every StreamApiConfig__Security__* line
```

```bash
docker stack deploy -c docker-compose.bridge-secure.yml bridge
```

Security only activates when one of `SaslUsername` / `SslCaLocation` /
`SslCertificateLocation` is non-empty, so removing them is sufficient. The
plaintext listener never went away.

To revert the broker entirely: `docker stack deploy -c docker-compose.kafka.yml kafka`.

---

## 8. Going to production

Once a scenario is validated:

1. Move **all** clients to the chosen secured listener.
2. Change `KAFKA_INTER_BROKER_LISTENER_NAME` to that listener.
3. Remove `PLAINTEXT` and `PLAINTEXT_HOST` from `KAFKA_LISTENERS`,
   `KAFKA_ADVERTISED_LISTENERS` and `KAFKA_LISTENER_SECURITY_PROTOCOL_MAP`.
4. Remove the now-unused secured listeners too — keep exactly one.
5. Move SASL passwords and the CIFS credentials to `docker secret`.

Step 3 is the only hard cutover, and by then everything else is proven.

> Note for step 3: with plaintext gone you lose the unauthenticated path used
> by `create-scram-users.sh`. Create SCRAM users **before** removing it, or plan
> to use `--add-scram` at format time.

---

## Troubleshooting

### Broker exits immediately: `configure: line 18: !1: unbound variable`

The image's `/etc/kafka/docker/configure` detects `SSL://` in
`KAFKA_ADVERTISED_LISTENERS` and then hard-requires
`KAFKA_SSL_KEYSTORE_FILENAME`, `KAFKA_SSL_KEYSTORE_CREDENTIALS` and
`KAFKA_SSL_KEY_CREDENTIALS`. It runs under `set -u`, so supplying
`KAFKA_SSL_KEYSTORE_LOCATION` instead kills the container before Kafka starts.

**Keystore must use FILENAME/CREDENTIALS. Truststore must be set directly** —
the script only wires up truststore indirection when the *global*
`ssl.client.auth` is `required`/`requested`, and ours is `none` because client
certs are demanded per-listener. Both already correct in the provided file.

### Broker exits: `Could not find a 'KafkaServer' or 'scrammtls.KafkaServer' entry`

Kafka requires a JAAS entry to exist for a SCRAM-enabled listener even though
the credentials live in cluster metadata. Provided by
`secrets/kafka_server_jaas.conf` + the `KAFKA_OPTS` line. Make sure that file
was included when you copied `secrets/` to the Kafka node.

### TLS fails only from outside the swarm

The broker cert SAN must include the address used. `10.104.10.89` is included
by default; anything else needs `EXTRA_SANS` at generation time (§1).

### Client connects but no data appears

Almost certainly not a security problem — check `StreamApiConfig__Domain`
(`VitualTest`) matches the topic prefix you're looking at in Kafka UI.

### `secrets` directory empty inside the container

Swarm doesn't copy local files to remote nodes. Confirm the absolute path
exists **on the target node** and is owned by uid 1000 on the Kafka node.

---

## Credentials reference

| Username | Password | Used by |
|---|---|---|
| `admin` | `admin-secret` | kafka-ui, admin tooling |
| `streamuser` | `stream-secret` | Bridge Service, VPS, Gateway |

Certificate store password: `changeit` (override with `CERT_PASSWORD=...`).
`client.key` is unencrypted, so no `SslKeyPassword` is needed.

These are test credentials. Change them, and move them to `docker secret`,
before any of this becomes permanent.
