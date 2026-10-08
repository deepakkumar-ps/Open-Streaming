# Fragmented Broker

Decentralized Kafka broker examples: **one self-contained stack per security
configuration**. Each folder is a single-broker KRaft Kafka setup (no ZooKeeper) that
demonstrates exactly one authentication and encryption model end to end, with its own
Compose file, certificate generator and README.

This is the clearer place to study or demonstrate one security model in isolation. When
the goal is to migrate a running system rather than study a model, use the
[Unified Broker](../Unified%20Broker/) instead — it exposes every posture at once on a
single broker, so clients move across one at a time without a broker redeploy.

Setup instructions live inside each folder. This page only explains what each one is
for.

---

## Security Configurations

### [SASL or PLAIN](SASL%20or%20PLAIN/)

The baseline the other examples build on. Client and inter-broker listeners use
`SASL_PLAINTEXT`: SASL/PLAIN username and password authentication with **no
encryption** — traffic is plaintext on the wire. No certificates and no TLS setup, just
a JAAS config.

Suited to development and isolated networks; the simplest starting point.

### [SASL + SSL or TLS](SASL%20+%20SSL%20or%20TLS/)

Listeners use `SASL_SSL`: SASL/PLAIN for authentication, TLS for encryption. With
`ssl.client.auth=none`, clients need only the CA certificate to verify the broker — they
present no certificate of their own.

The usual choice when password-based authentication is acceptable but traffic must be
encrypted.

### [Mutual TLS (mTLS)](Mutual%20TLS%20(mTLS)/)

The `SSL` protocol with no SASL at all — authentication is purely certificate-based.
`ssl.client.auth=required` means every client must present its own certificate signed by
the example CA or the handshake is rejected, and the client's identity is the
certificate subject (for example `CN=client`).

Suited to environments where there are no passwords to manage.

### [SASL or PLAIN + Mutual TLS (mTLS)](SASL%20or%20PLAIN%20+%20Mutual%20TLS%20(mTLS)/)

Both layers combined: `SASL_SSL` with `ssl.client.auth=required`, so a client needs a
valid password **and** a valid client certificate. Both must pass. The session principal
comes from SASL — the certificate DN is not used for identity when SASL is in play.

### [SASL or SCRAM-SHA-256 + mTLS](SASL%20or%20SCRAM-SHA-256%20+%20mTLS/)

The same combined shape, but the SASL mechanism is `SCRAM-SHA-256` rather than `PLAIN`,
giving salted password hashing instead of passwords compared in the clear.

This folder needs one extra concept. SCRAM credentials are not read from a static JAAS
file — they live in cluster metadata, normally added over an already-authenticated admin
connection. Since every listener here demands SASL and mTLS from first boot, there is no
unauthenticated path to create the first user, so the stack seeds both users into the
KRaft metadata log at format time via a one-shot init service. Its README explains the
bootstrap and how to reset it.

---

## At a Glance

| Configuration | Protocol | Authentication | Encryption | Client cert | Certs to generate |
|---|---|---|---|---|---|
| [SASL or PLAIN](SASL%20or%20PLAIN/) | `SASL_PLAINTEXT` | Password | — | — | None |
| [SASL + SSL or TLS](SASL%20+%20SSL%20or%20TLS/) | `SASL_SSL` | Password | TLS | — | Broker only |
| [Mutual TLS (mTLS)](Mutual%20TLS%20(mTLS)/) | `SSL` | Certificate | TLS | Required | Broker + client |
| [SASL or PLAIN + mTLS](SASL%20or%20PLAIN%20+%20Mutual%20TLS%20(mTLS)/) | `SASL_SSL` | Password **and** certificate | TLS | Required | Broker + client |
| [SASL or SCRAM-SHA-256 + mTLS](SASL%20or%20SCRAM-SHA-256%20+%20mTLS/) | `SASL_SSL` | SCRAM password hashing **and** certificate | TLS | Required | Broker + client |

Verification status differs by folder and each README records its own: the SASL/PLAIN,
SASL+SSL and SCRAM+mTLS stacks have been run end-to-end with Kafka UI reporting the
cluster `ONLINE`; for the two mTLS-only and SASL+mTLS stacks, only certificate
generation has been verified so far.

---

## Shared Reference

### [bridge service sample config](bridge%20service%20sample%20config/)

Reference configuration for the Bridge Service client, not a broker stack.

| File | What it is |
|---|---|
| `AppConfig.json` | A complete Bridge Service configuration — broker URL, domain, stream-to-partition mappings and the `Security` block a client uses to reach a secured broker. Exists as a starting point to copy rather than write from scratch. |
| `kafka-publisher-broker.json` | The Kafka publisher's broker-side settings, referenced from `AppConfig.json`. |

Each configuration folder's README shows the `Security` block for its own posture; this
sample shows where that block sits in the wider file.

### Common to every folder

- **Single-broker KRaft** — no ZooKeeper anywhere. The controller listener stays
  `PLAINTEXT`, since it is single-node and intra-cluster only.
- **One stack at a time.** Every folder uses the same container names and host ports
  (`9094` and `8080`), so bring one down before bringing another up.
- **Shared network.** All stacks expect the `shared_network` Docker network to exist
  before deployment.
- **Endpoints** are consistent throughout: broker on `kafka:9092` in-network and
  `localhost:9094` from the host, with Kafka UI on `localhost:8080`.
- **Certificates** are written to each folder's own gitignored `secrets/` directory by
  its `generate-certs.sh` (Linux, Git Bash) or `generate-certs.ps1` (Windows). Stores
  use PKCS12 because the `apache/kafka` image's configure script expects a keystore
  filename plus credentials-file pair, and PKCS12 can be built with plain `openssl`.
- **Test credentials** are the same across the SASL examples — `admin` / `admin-secret`
  and `streamuser` / `stream-secret`, with `changeit` for certificate stores. Change
  them before any of this becomes permanent.
- **Hostname verification works as-is.** Broker certificate SANs cover both `kafka` and
  `localhost`, so connections succeed from inside the Docker network and from the host.
  Never work around a TLS failure by disabling verification — check the SANs instead.

---

For the repository-wide overview see the [root README](../../README.md); for the other
deployment categories in this area see [Virtual Machine Streaming](../README.md).
