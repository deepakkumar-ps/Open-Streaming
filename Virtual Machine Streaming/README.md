# Virtual Machine Streaming

Docker Swarm and multi-VM deployment examples for Open Streaming. Where
[Local Streaming](../Local%20Streaming/) runs everything on one machine, these examples
split the pipeline across virtual machines — typically a Bridge node and a Kafka node
on a shared overlay network.

The area is organised into three deployment categories. Each folder carries its own
setup instructions; this page only explains what each one is for.

---

## Deployment Categories

### [Bridge](Bridge/)

Bridge Service deployment examples. The Bridge publishes ADS telemetry into Kafka, and
the two variants here differ only in **where the Bridge reads its PGVS and DTVS assets
from**.

| Folder | Asset source |
|---|---|
| [Bridge Local Assets](Bridge/Bridge%20Local%20Assets/) | The Bridge reads PGVS and DTVS from the deployment machine's own local filesystem. Use this when the assets are staged on the VM itself. |
| [Bridge Network Drive Assets](Bridge/Bridge%20Network%20Drive%20Assets/) | The Bridge reads PGVS and DTVS from the shared network drive (T drive), mounted into the container. Use this when assets are managed centrally. |

Pick one variant per deployment — they are alternatives, not layers.

### [Unified Broker](Unified%20Broker/)

A centralized Kafka broker example, plus the supporting Open Streaming configuration
files that go with it. A single Kafka stack exposes every supported security posture on
its own port simultaneously, so the broker is deployed **once** and a client moves
between postures by changing only its own configuration.

The existing plaintext listener stays untouched while the secured listeners are added
alongside it, which makes this the low-risk path for migrating a running system.

Detailed setup instructions — certificate generation, staging certificates across
nodes, stack deployment, per-posture client configuration and rollback — live inside
that folder's README.

### [Fragmented Broker](Fragmented%20Broker/)

Decentralized broker examples: one self-contained Kafka stack per security
configuration. Each folder demonstrates **a single authentication and encryption
model** end to end, which makes it the clearer place to study one posture without the
other listeners in the way.

| Folder | Security model |
|---|---|
| [SASL or PLAIN](Fragmented%20Broker/SASL%20or%20PLAIN/) | SASL/PLAIN username and password, no encryption. The baseline. |
| [SASL + SSL or TLS](Fragmented%20Broker/SASL%20+%20SSL%20or%20TLS/) | SASL/PLAIN over TLS. Clients verify the broker but present no certificate of their own. |
| [Mutual TLS (mTLS)](Fragmented%20Broker/Mutual%20TLS%20(mTLS)/) | Certificate-based authentication only — no passwords. Every client presents its own certificate. |
| [SASL or PLAIN + Mutual TLS (mTLS)](Fragmented%20Broker/SASL%20or%20PLAIN%20+%20Mutual%20TLS%20(mTLS)/) | Both layers: password **and** client certificate must pass. |
| [SASL or SCRAM-SHA-256 + mTLS](Fragmented%20Broker/SASL%20or%20SCRAM-SHA-256%20+%20mTLS/) | SCRAM-SHA-256 password hashing plus client certificates, with credentials held in cluster metadata. |

The folder also holds [bridge service sample config](Fragmented%20Broker/bridge%20service%20sample%20config/) —
reference `AppConfig.json` and broker configuration files showing how a Bridge Service
client is pointed at a secured broker.

---

## Choosing Between Unified and Fragmented

| | Unified Broker | Fragmented Broker |
|---|---|---|
| Broker deployments | One, serving all postures | One per posture |
| Switching posture | Change client config only | Redeploy a different stack |
| Existing plaintext traffic | Stays up throughout | Torn down when switching |
| Best for | Migrating a live system | Studying or demonstrating one model |

---

For a repository-wide overview and the full list of supported security postures, see
the [root README](../README.md).
