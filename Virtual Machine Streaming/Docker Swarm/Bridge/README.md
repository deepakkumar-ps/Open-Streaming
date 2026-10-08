# Bridge

Bridge Service deployment examples for Docker Swarm. The Bridge Service reads the
telemetry configuration assets — PGVs, DTVs, config and PUL files — and publishes ADS
telemetry into Kafka for ATLAS and the other Open Streaming consumers to read back.

The two folders here are **alternatives, not layers**. They differ in where the Bridge
reads those assets from, and that one decision changes the shape of the whole
deployment.

---

## Deployment Variants

### [Bridge Local Assets](Bridge%20Local%20Assets/)

The Bridge reads PGVs and DTVs from the **deployment machine's own local filesystem**,
bind-mounted into the container from absolute paths on the Bridge node. Deploys the
Bridge Service alone, joining an existing Kafka stack over a shared external network.

Use this when assets are staged on the VM itself and Kafka is already deployed
separately. It is the smaller and simpler of the two.

### [Bridge Network Drive Assets](Bridge%20Network%20Drive%20Assets/)

The Bridge reads PGVs and DTVs from the **shared network drive (T drive)**, mounted into
the containers as a CIFS volume. Deploys a full stack — Kafka and Kafka UI, the Bridge,
Virtual Parameter and Gateway services, and the file and config indexer services with
MongoDB behind them.

Use this when assets are managed centrally and several nodes must see the same set.
Centralized assets are what make the indexer services worthwhile, which is why they
ship together.

---

## At a Glance

| | Bridge Local Assets | Bridge Network Drive Assets |
|---|---|---|
| Asset source | Local filesystem on the Bridge node | CIFS mount of the T drive |
| Services deployed | Bridge Service only | Full stack incl. Kafka, VPS, Gateway, indexers, MongoDB |
| Kafka | Expected to exist already | Deployed as part of the stack |
| Network | External `shared_network` | Overlay `stream_net`, created by the stack |
| Asset management | Per-node, staged by hand | Central, shared across nodes |
| Node labels used | `role == bridge` | `role == kafka`, `role == bridge-service`, `role == services` |

Both variants publish the Bridge Service on ports `9697` and `10010`, and both expect
clients to reach Kafka at `kafka:9092`, which resolves across machines over the Swarm
network.

---

## Before Deploying Either

- **Swarm nodes must be labelled.** Every service is pinned with a placement constraint,
  and an unlabelled node means the service is scheduled nowhere and simply stays
  pending. The two folders use different label values — check the table above.
- **Bind-mount paths and drive shares must already exist on the target node.** Swarm
  does not copy local files to remote nodes, so a path that is missing produces an
  empty directory inside the container rather than an error.
- **The Bridge domain must match the ATLAS Stream Recorder**, along with the stream
  creation strategy and partition mapping, or data will be published where nothing is
  listening.

Each folder's README carries the setup steps, the paths and environment variables it
expects, and its own verification notes.

---

## Related

- [Unified Broker](../Unified%20Broker/) and [Fragmented Broker](../Fragmented%20Broker/) —
  the Kafka side these Bridge deployments publish into, including how to point the
  Bridge at a secured listener.
- [Local Streaming](../../Local%20Streaming/) — the same pipeline on a single machine,
  useful for seeing the end-to-end flow before deploying across VMs.
- [Virtual Machine Streaming](../README.md) — the other deployment categories.
