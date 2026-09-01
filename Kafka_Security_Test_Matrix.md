# Kafka Security Test Matrix — Stream API / Bridge Service

Validates the `StreamApiConfig.Security` block (used identically by the Stream API
and the Bridge Service's `AppConfig.json`) against every Kafka broker security
posture it's supposed to support, using the five docker-compose scenarios in this
folder plus the real Bridge Service sample config (`bridge service sample
config/MSOConfigs_P/`).

Reference: [Kafka Security Configuration](https://atlas.motionapplied.com/developer-resources/secu4/stream_api/reference_docs/configuration/kafka-security/)

---

## 1. What's being validated

The `Security` block has two independent axes plus a client-cert toggle:

| Axis | Values |
|---|---|
| **Encryption** (`Protocol`) | `Plaintext`, `Ssl`, `SaslPlaintext`, `SaslSsl` |
| **Authentication** (`Mechanism`, only when `Sasl*`) | `Plain`, `ScramSha256`, `ScramSha512` |
| **Client certificate** (mTLS) | absent (`SslCertificateLocation`/`SslKeyLocation` empty) vs present |

A full test pass means: for every broker posture we claim to support, a client
using the matching `Security` block connects and produces/consumes correctly,
**and** a client using the *wrong* credentials or *wrong* certificate is
correctly rejected. Testing only the happy path each of the five READMEs
describes ("kafka-ui connects and reports the cluster ONLINE") proves the
config is *accepted* — it doesn't prove the broker is actually enforcing it.

---

## 2. Coverage matrix

| # | Scenario folder | `Protocol` | `Mechanism` | Client cert required? | Broker listener | Ports (host) | Status per README |
|---|---|---|---|---|---|---|---|
| 1 | `kafka-no-zookeeper-sassl` | `SaslPlaintext` | `Plain` | No | `SASL_PLAINTEXT` | 9094, 8080 | ✅ Verified — broker, kafka-ui, **and bridge service** connected |
| 2 | `kafka-no-zookeeper-sasl-ssl` | `SaslSsl` | `Plain` | No (`ssl.client.auth=none`) | `SASL_SSL` | 9094, 8080 | ✅ Verified — broker + kafka-ui |
| 3 | `kafka-no-zookeeper-ssl-mtls` | `Ssl` | — | **Yes** (`required`) | `SSL` | 9094, 8080 | ⚠️ **Not verified** — cert generation only, README says so explicitly |
| 4 | `kafka-no-zookeeper-sasl-mtls` | `SaslSsl` | `Plain` | **Yes** (`required`) | `SASL_SSL` | 9094, 8080 | ⚠️ **Not verified** — cert generation only, README says so explicitly |
| 5 | `kafka-no-zookeeper-sasl-scram-mtls` | `SaslSsl` | `ScramSha256` | **Yes** (`required`) | `SASL_SSL` | 9094, 8080 | ✅ Verified — broker + kafka-ui, including a SCRAM-bootstrap workaround (see §5.5) |

Every folder reuses the same container names (`kafka-broker-1`, `kafka-ui-1`) and
host ports (9094, 8080) — **only one scenario can run at a time.** `docker
compose down` the current one before bringing up the next.

---

## 3. Coverage gaps — not represented by any scenario folder

Checking the matrix above against everything the docs page documents surfaces
three gaps worth closing before calling this feature fully tested:

| Gap | Why it matters | Suggested fix |
|---|---|---|
| **`Ssl` with `ssl.client.auth=none`** (one-way TLS — verify the broker, no client cert) | This is the docs page's own first SSL example (`"SSL (One-Way TLS - Broker Verification Only)"`). None of the 5 folders test it — `ssl-mtls` always requires a client cert. It's the simplest SSL case and the most likely one a customer tries first. | Clone `kafka-no-zookeeper-ssl-mtls`, set `KAFKA_SSL_CLIENT_AUTH: "none"`, drop the client cert from the `Security` block. |
| **`ScramSha512`** | Documented as a valid `Mechanism` alongside `ScramSha256`; only `ScramSha256` has been exercised (in scenario 5). | Either add a 6th folder, or confirm with the team that `ScramSha512` shares enough code path with `ScramSha256` that one is a reasonable proxy — and say so explicitly rather than leaving it silently untested. |
| **SASL/SCRAM over TLS *without* mTLS** — the exact combination under the page's `#kafka-security-sasl-ssl` anchor (`SaslSsl` + `ScramSha512`, **no client cert**) | This is the specific example that prompted this test pass. Scenario 5 tests SCRAM, but always paired with mandatory mTLS — the SCRAM-alone-over-TLS case is untested. | Clone scenario 5, set `KAFKA_SSL_CLIENT_AUTH: "none"`, drop the client cert from the `Security` block. |

None of these are hard to add — each is a small edit of an existing
docker-compose.yml — but until they exist, "SASL_SSL" as a whole is only
partially covered.

---

## 4. Shared prerequisites (all scenarios)

- Docker Desktop running, `docker` and `docker compose` on `PATH`.
- `openssl` available for certificate generation (Git Bash on Windows, or native `openssl` on `PATH` for the `.ps1` variants).
- The shared network, created once:
  ```bash
  docker network create shared_network
  ```
  (Safe to re-run — errors harmlessly if it already exists.)
- Nothing else already bound to host ports **9094** or **8080**.
- A Kafka client to test with, in order of how close it is to production:
  1. **kafka-ui** (browser, already wired into every compose file) — proves the broker's security config is internally consistent (its own inter-broker + advertised listeners work).
  2. **`kafka-console-producer.sh` / `kafka-console-consumer.sh`** (from inside the `kafka` container, or a throwaway client container) with a matching `client.properties` — proves a *generic* Kafka client can authenticate, independent of anything Motion Applied-specific.
  3. **The Stream API / Bridge Service itself**, using the `Security` block from each README (or the real sample in `bridge service sample config/MSOConfigs_P/AppConfig.json`) — proves the thing we actually ship works.

  Step 2 matters: if the Stream API fails to connect, it isolates whether the
  problem is the broker's security config or something specific to the Stream
  API's `librdkafka`-based client.

---

## 5. Per-scenario test procedures

### 5.1 Scenario 1 — `kafka-no-zookeeper-sassl` (SASL/PLAIN, no encryption)

**Purpose:** baseline — authentication only, no TLS. This is the one already
proven against the real bridge service, so it's the reference for "known good."

**Bring-up**

```bash
cd kafka-no-zookeeper-sassl
docker compose up -d
docker compose logs -f kafka   # watch for "started (kafka.server.KafkaServer)"
```

**Smoke test** — open http://localhost:8080, confirm the `local` cluster shows
**Online** and topics are browsable.

**Functional test** — point the Stream API / Bridge Service at it:

```json
"BrokerUrl": "localhost:9094",
"Security": {
  "SaslUsername": "streamuser",
  "SaslPassword": "stream-secret",
  "Protocol": "SaslPlaintext",
  "Mechanism": "Plain"
}
```

(If the Stream API itself is running inside `shared_network` as a container,
use `"BrokerUrl": "kafka:9092"` instead — see §6.2.)

Confirm: session creates, `ConfigurationPacket` and data packets land on the
expected topics (visible in kafka-ui), no auth errors in the Stream API log.

**Negative tests**

| Test | Change | Expected result |
|---|---|---|
| Wrong password | `SaslPassword: "wrong"` | Connection fails with a SASL authentication error — not a silent hang or a generic timeout |
| No `Security` block at all | Remove the block entirely | Fails cleanly (the broker *requires* SASL on this listener) — confirms the broker is actually enforcing auth, not just accepting it optionally |

---

### 5.2 Scenario 2 — `kafka-no-zookeeper-sasl-ssl` (SASL/PLAIN + TLS, no client cert)

**Purpose:** encryption + authentication, broker-verification-only TLS (the
combination under the page's `#kafka-security-sasl-ssl` anchor, minus SCRAM).

**Bring-up**

```bash
cd kafka-no-zookeeper-sasl-ssl
./generate-certs.sh          # or: .\generate-certs.ps1 on native PowerShell
docker compose up -d
```

**Smoke test** — http://localhost:8080, confirm **Online**. kafka-ui's own
config only needs the truststore (no client keystore) — matches
`ssl.client.auth=none`.

**Functional test**

```json
"BrokerUrl": "localhost:9094",
"Security": {
  "Protocol": "SaslSsl",
  "Mechanism": "Plain",
  "SaslUsername": "streamuser",
  "SaslPassword": "stream-secret",
  "SslCaLocation": "<repo>/kafka-no-zookeeper-sasl-ssl/secrets/ca.crt"
}
```

Note there is **no** `SslCertificateLocation` / `SslKeyLocation` — confirm the
connection still succeeds without them (proves `ssl.client.auth=none` is
actually in effect on the broker side, not silently requiring a cert anyway).

**Negative tests**

| Test | Change | Expected result |
|---|---|---|
| Wrong `SaslPassword` | as above | SASL auth failure |
| Wrong / missing `SslCaLocation` | point at a different (unrelated) CA, or omit it | TLS trust failure — the *client* refuses to trust the broker's certificate. This is a client-side rejection, not a broker rejection, but it's the mechanism customers will hit if they mistype a cert path. |

---

### 5.3 Scenario 3 — `kafka-no-zookeeper-ssl-mtls` (mTLS only, no SASL) — ⚠️ not yet verified

**This one needs a first successful run before anything else** — the README is
explicit that only certificate generation has been checked, not the stack
itself.

**Bring-up**

```bash
cd kafka-no-zookeeper-ssl-mtls
./generate-certs.sh
docker compose up -d
docker compose logs -f kafka
docker compose logs -f kafka-ui
```

If it doesn't come up cleanly, that's the first finding to record — capture
the exact error from both logs before troubleshooting further.

**Smoke test** — http://localhost:8080. kafka-ui here needs its own client
cert (`kafka-ui.keystore.p12`) — confirm it authenticates using nothing but
the certificate (there is no SASL layer to fall back on in this scenario).

**Functional test**

```json
"BrokerUrl": "localhost:9094",
"Security": {
  "Protocol": "Ssl",
  "SslCaLocation": "<repo>/kafka-no-zookeeper-ssl-mtls/secrets/ca.crt",
  "SslCertificateLocation": "<repo>/kafka-no-zookeeper-ssl-mtls/secrets/client.crt",
  "SslKeyLocation": "<repo>/kafka-no-zookeeper-ssl-mtls/secrets/client.key"
}
```

No `SaslUsername`/`Mechanism` — the certificate *is* the identity here
(principal = the cert's subject DN, e.g. `CN=client`).

**Negative tests**

| Test | Change | Expected result |
|---|---|---|
| Omit `SslCertificateLocation`/`SslKeyLocation` | remove both | TLS handshake rejected — `ssl.client.auth=required` means the broker refuses to complete the handshake at all without a client cert |
| Certificate not signed by this scenario's CA | generate an unrelated self-signed cert, or reuse a cert from a *different* scenario folder | Handshake rejected — confirms the broker is actually checking the signing chain against its own truststore, not just checking "a cert was presented" |

---

### 5.4 Scenario 4 — `kafka-no-zookeeper-sasl-mtls` (SASL/PLAIN + mTLS) — ⚠️ not yet verified

Same "run it for the first time" caveat as 5.3.

**Bring-up**

```bash
cd kafka-no-zookeeper-sasl-mtls
./generate-certs.sh
docker compose up -d
docker compose logs -f kafka
```

**Smoke test** — http://localhost:8080, **Online**.

**Functional test**

```json
"BrokerUrl": "localhost:9094",
"Security": {
  "Protocol": "SaslSsl",
  "Mechanism": "Plain",
  "SaslUsername": "streamuser",
  "SaslPassword": "stream-secret",
  "SslCaLocation": "<repo>/kafka-no-zookeeper-sasl-mtls/secrets/ca.crt",
  "SslCertificateLocation": "<repo>/kafka-no-zookeeper-sasl-mtls/secrets/client.crt",
  "SslKeyLocation": "<repo>/kafka-no-zookeeper-sasl-mtls/secrets/client.key"
}
```

This is the "both layers at once" case — the README notes the session
principal comes from SASL, not the certificate DN, when both are present.
Worth confirming that's actually true (see negative test below).

**Negative tests**

| Test | Change | Expected result |
|---|---|---|
| Correct SASL, missing/wrong client cert | drop the `Ssl*` fields, or use an unsigned cert | Rejected at the TLS layer — SASL never even gets evaluated, since the handshake fails first |
| Correct client cert, wrong SASL password | keep certs, set `SaslPassword: "wrong"` | TLS handshake succeeds, then SASL authentication fails — confirms **both** layers are independently enforced, not just one masking the other |

---

### 5.5 Scenario 5 — `kafka-no-zookeeper-sasl-scram-mtls` (SASL/SCRAM-SHA-256 + mTLS)

**Purpose:** the most production-realistic combination — SCRAM credentials
aren't static (unlike PLAIN), so this is also the scenario that exercises the
trickiest bootstrap problem.

**Why this one is different:** SCRAM credentials live in the cluster's KRaft
metadata, normally added via `kafka-configs.sh` over an already-authenticated
connection. But every listener here demands SASL+mTLS from the first boot —
there's no unauthenticated path in to create that first user. The fix baked
into `docker-compose.yml` is a one-shot `kafka-init` service that runs
`kafka-storage.sh format --add-scram ...` *before* the broker starts,
injecting both users directly into the metadata log at format time.

**Bring-up**

```bash
cd kafka-no-zookeeper-sasl-scram-mtls
./generate-certs.sh
docker compose up -d
docker compose logs -f kafka-init   # confirm the format/add-scram step succeeded
docker compose logs -f kafka
```

**Smoke test** — http://localhost:8080, **Online**, using SCRAM-SHA-256 creds.

**Functional test**

```json
"BrokerUrl": "localhost:9094",
"Security": {
  "Protocol": "SaslSsl",
  "Mechanism": "ScramSha256",
  "SaslUsername": "streamuser",
  "SaslPassword": "stream-secret",
  "SslCaLocation": "<repo>/kafka-no-zookeeper-sasl-scram-mtls/secrets/ca.crt",
  "SslCertificateLocation": "<repo>/kafka-no-zookeeper-sasl-scram-mtls/secrets/client.crt",
  "SslKeyLocation": "<repo>/kafka-no-zookeeper-sasl-scram-mtls/secrets/client.key"
}
```

**Negative tests**

| Test | Change | Expected result |
|---|---|---|
| Correct cert, wrong SCRAM password | `SaslPassword: "wrong"` | SASL failure after a successful TLS handshake |
| Correct cert, unknown username | `SaslUsername: "nobody"` | Same generic auth failure — SCRAM shouldn't leak whether the *user* or the *password* was wrong |
| **Restart persistence** (SCRAM-specific) | `docker compose restart kafka` (not `down` — keep the volume) | The broker must come back up and accept the same SCRAM credentials without re-running `kafka-init` — proves credentials are durably in the metadata log, not an artifact of the bootstrap step alone |
| **Reset-from-scratch** (documented in the README) | `docker compose down && docker volume rm kafka-no-zookeeper-sasl-scram-mtls_kafka-scram-data`, then bring up again | `kafka-init` reformats and re-adds both users — confirms the reset procedure the README documents actually works, not just that it's written down |

---

## 6. Cross-cutting checks (run once, independent of scenario)

### 6.1 Regression: security config absent still works unsecured

Per the docs page: *"When no credentials are set, the connection remains
unsecured."* Point the Stream API at a plain, non-secured broker (the
standard unsecured docker-compose from `docker-setup.md`, not any scenario
here) with **no** `Security` block at all. Confirms adding the `Security`
feature didn't change default (unsecured) behaviour for every existing
customer not using it.

### 6.2 In-network vs host address

Every scenario advertises two listeners — `kafka:9092` (for clients on
`shared_network`, e.g. a containerized Stream API) and `localhost:9094` (for
clients on the host). Test **both** at least once across the matrix, not just
`localhost:9094` every time — a containerized Stream API using the wrong one
is a realistic misconfiguration, and the two listeners have independently
configured security protocol maps that could in principle drift apart.

### 6.3 Certificate SAN coverage

The mTLS/SSL READMEs note the broker cert's SAN covers both `kafka` and
`localhost`, "so hostname verification works" from either address without
disabling `ssl.endpoint.identification.algorithm`. Explicitly confirm this —
i.e. do *not* disable hostname verification to make a test pass; if it only
works with verification disabled, that's a finding, not a workaround.

### 6.4 Malformed `Security` block

Set `Protocol: "Ssl"` but leave `SslCaLocation` empty (a plausible typo/copy-paste
mistake). Confirm the Stream API fails with a clear configuration error
rather than a confusing connection timeout — this is the kind of edge case
the activation-trigger logic (*"security is applied when any of
`SaslUsername`, `SslCaLocation`, or `SslCertificateLocation` is
non-empty"*) makes possible to hit accidentally.

---

## 7. Results tracker

| Scenario | Smoke (kafka-ui) | Functional (Stream API / Bridge Service) | Negative test(s) | Notes |
|---|---|---|---|---|
| 1. SASL/PLAIN | ☐ | ☐ | ☐ | |
| 2. SASL_SSL/PLAIN, no mTLS | ☐ | ☐ | ☐ | |
| 3. SSL/mTLS only | ☐ | ☐ | ☐ | First-ever run — capture full logs regardless of outcome |
| 4. SASL_SSL/PLAIN + mTLS | ☐ | ☐ | ☐ | First-ever run — capture full logs regardless of outcome |
| 5. SASL_SSL/SCRAM-256 + mTLS | ☐ | ☐ | ☐ | Include restart-persistence + reset-from-scratch checks |
| 6.1 Regression (no security) | ☐ | — | — | |
| 6.2 In-network address (`kafka:9092`) | ☐ | ☐ | — | |
| 6.4 Malformed config | — | ☐ | — | |
| **Gap** — SSL one-way (no mTLS) | ☐ *(needs new folder — §3)* | ☐ | ☐ | |
| **Gap** — SASL_SSL/SCRAM, no mTLS | ☐ *(needs new folder — §3)* | ☐ | ☐ | |
| **Gap** — `ScramSha512` | — | ☐ *(needs new folder or explicit deferral — §3)* | — | |

---

## 8. Appendix — quick reference

### Credentials (all SASL scenarios)

| Username | Password |
|---|---|
| `admin` | `admin-secret` |
| `streamuser` | `stream-secret` |

### Ports

| Service | In-network | Host |
|---|---|---|
| Kafka broker | `kafka:9092` | `localhost:9094` |
| Kafka UI | — | `localhost:8080` |

### Certificate store password

All keystores/truststores use `changeit` (overridable per-run via
`CERT_PASSWORD=... ./generate-certs.sh`). `client.key` (PEM, for
`librdkafka`/Stream API clients) is unencrypted — no `SslKeyPassword` needed
unless you regenerate with a passphrase.

### Switching scenarios

```bash
docker compose down          # in the current scenario folder
cd ../<next-scenario>
./generate-certs.sh          # if the folder has one
docker compose up -d
```

### The real Bridge Service sample

`bridge service sample config/MSOConfigs_P/AppConfig.json` uses
`Protocol: "SaslPlaintext"` / `Mechanism: "Plain"` — it maps to **Scenario 1**
and is the one config in this whole set that's a genuine production sample
rather than a docs illustration. Useful as the reference for "what a real
`BridgeConfig`/`EssentialsConfig`/`Serilog` block looks like around the
`Security` section," beyond just the security fields themselves.
