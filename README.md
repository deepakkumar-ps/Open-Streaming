# Open Streaming

Open Streaming is a Kafka-based telemetry streaming pipeline. Data is published from
ADS through the **Bridge Service** into **Kafka**, where downstream consumers such as
**ATLAS** and the Gateway and Virtual Parameter services read it back.

This repository holds the deployment examples for that pipeline — Docker Compose and
Docker Swarm stacks for the Bridge Service and Kafka, together with reference
configurations for every Kafka security posture the project supports. It is a
navigation hub: each folder below carries its own setup instructions.

![Image showing the repository structure](Structure.jpg)

---

## Repository Structure

### [Local Streaming](Local%20Streaming/)

A self-contained local Docker environment for learning, development and quick
validation. One Compose file brings up Kafka and Kafka UI on a single machine, and the
local Bridge Service publishes ADS telemetry into it so ATLAS can consume it — no VMs,
no overlay network, no remote IPs.

Start here to see the end-to-end flow working before touching any shared
infrastructure.

### [Virtual Machine Streaming](Virtual%20Machine%20Streaming/)

Docker Swarm and multi-VM deployment examples for the Bridge Service, Kafka and the
supporting Open Streaming infrastructure. This is where the realistic deployments live:
the Bridge Service running against local or network-drive assets, and Kafka deployed
either as one centralized broker or as separate per-security-model brokers.

See the folder's own README for a breakdown of the deployment categories.

---

## Kafka Security Options

Five security postures are supported across the deployment examples. They are the
options currently under evaluation, and they differ only in how a client authenticates
and whether traffic on the wire is encrypted.

| Posture | Protocol | Authentication | Encryption | Client cert |
|---|---|---|---|---|
| **SASL/PLAIN** | `SASL_PLAINTEXT` | Username / password | None | — |
| **SASL + SSL/TLS** | `SASL_SSL` | Username / password | TLS (one-way) | — |
| **Mutual TLS (mTLS)** | `SSL` | Client certificate | TLS (mutual) | Required |
| **SASL/PLAIN + mTLS** | `SASL_SSL` | Password **and** certificate | TLS (mutual) | Required |
| **SASL/SCRAM-SHA-256 + mTLS** | `SASL_SSL` | SCRAM password hashing **and** certificate | TLS (mutual) | Required |

SCRAM credentials live in the cluster's metadata rather than in a static JAAS file,
which is why that posture needs a bootstrap path to create the first user.

### Two ways to deploy them

| Approach | Where | Idea |
|---|---|---|
| **Unified Broker** | [Virtual Machine Streaming/Unified Broker](Virtual%20Machine%20Streaming/Unified%20Broker/) | One Kafka stack exposes every posture on its own port at the same time. Deploy the broker once and switch posture by changing only the client config. |
| **Fragmented Broker** | [Virtual Machine Streaming/Fragmented Broker](Virtual%20Machine%20Streaming/Fragmented%20Broker/) | One self-contained broker stack per posture. Each folder demonstrates a single security model in isolation. |

The unified approach keeps the existing plaintext listener untouched while secured
listeners are added alongside it, which mirrors the real migration path: add a
listener, move clients across one at a time, then retire plaintext. The fragmented
approach is easier to read when you only want to study one model.

---

## Common Prerequisites

- **Docker** and **Docker Compose** (Docker Swarm for the multi-VM examples)
- **OpenSSL** for the certificate-based postures — pre-installed on Linux and macOS,
  available via Git Bash on Windows
- A shared Docker network, created before bringing up any local stack:

  ```bash
  docker network create shared_network
  ```

---

## Where to Go Next

| I want to… | Go to |
|---|---|
| See the pipeline working on my own machine | [Local Streaming](Local%20Streaming/) |
| Deploy the Bridge Service to a VM | [Virtual Machine Streaming/Bridge](Virtual%20Machine%20Streaming/Bridge/) |
| Deploy one broker serving every security posture | [Virtual Machine Streaming/Unified Broker](Virtual%20Machine%20Streaming/Unified%20Broker/) |
| Study a single security model in isolation | [Virtual Machine Streaming/Fragmented Broker](Virtual%20Machine%20Streaming/Fragmented%20Broker/) |

Detailed setup instructions, certificate generation and client configuration examples
live in the README of each folder listed above.

---

## Notes

- All broker examples run **KRaft mode** — no ZooKeeper.
- Test credentials are used throughout (`admin` / `streamuser`). Change them, and move
  them to `docker secret`, before any of this becomes permanent.
- Broker certificates carry SANs for both the in-container hostname and the address
  clients reach the broker on. Never work around a hostname-verification failure by
  disabling verification.
