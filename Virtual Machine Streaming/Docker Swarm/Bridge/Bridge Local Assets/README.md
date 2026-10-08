# Bridge — Local Assets

Deploys the **Bridge Service on its own**, reading its PGVs and DTVs from the
deployment machine's **local filesystem**. Nothing is fetched from a network drive: the
assets are bind-mounted into the container from absolute paths on the Bridge node.

Kafka is **not** part of this stack. It is expected to be running already — see
[Unified Broker](../../Unified%20Broker/) or
[Fragmented Broker](../../Fragmented%20Broker/) — and the Bridge joins it over the
shared external network.

For the network-drive alternative, see
[Bridge Network Drive Assets](../Bridge%20Network%20Drive%20Assets/).

---

## What Gets Deployed

| Service | Image | Published ports |
|---|---|---|
| `bridge-service` | `atlasplatformdocker/bridge-service-host-dev:2.1.4.35-dev` | `9697`, `10010` |

One replica, pinned to the node labelled `role=bridge`, with a 4 CPU / 4 GB limit and a
1 GB reservation. The .NET GC is tuned for containers — a 3 GB heap ceiling, server and
concurrent GC enabled — so the service stays inside that memory limit rather than being
OOM-killed. `restart_policy` is `on-failure`.

Both ports are published through the Swarm routing mesh, so the service is reachable
from a Windows machine at `<bridge-node-IP>:9697` and `<bridge-node-IP>:10010`.

---

## Prerequisites

**1. The Swarm node must be labelled.** The placement constraint is
`node.labels.role == bridge`; without the label the service is scheduled nowhere and
stays pending with no error.

```bash
docker node update --label-add role=bridge <bridge-node>
```

**2. The shared network must exist.** It is declared `external: true`, so the stack will
not create it:

```bash
docker network create --driver overlay --attachable shared_network
```

**3. Kafka must be reachable at `kafka:9092`** on that network. The hostname resolves
across machines over the overlay network, so no IP address is needed.

---

## Stage the Assets

The two bind-mounted directories must **exist on the Bridge machine** before deploying.
Swarm does not copy local files to remote nodes — a missing path produces an empty
directory inside the container rather than a failure, which surfaces later as the Bridge
finding no configuration.

| Host path (on the Bridge node) | Container path | Holds |
|---|---|---|
| `/home/ocsautotest/docker-composes/BridgeService/Configs` | `/app/Configs` | Bridge configuration, including `AppConfig.json` |
| `/home/ocsautotest/docker-composes/BridgeService/EssentialFiles` | `/app/Essentials` | Essentials — PGVs, DTVs and config files |

```bash
sudo mkdir -p /home/ocsautotest/docker-composes/BridgeService/Configs \
              /home/ocsautotest/docker-composes/BridgeService/EssentialFiles
```

Then copy the configuration into `Configs/` and the assets into `EssentialFiles/`.

> The comment block at the top of `docker-compose.yml` refers to `/opt/bridge/...` and
> to a file named `docker-compose.bridge.yml`. The paths the file actually mounts are
> the ones in the table above, and the file is named `docker-compose.yml` — follow the
> table and the command below.

A reference `AppConfig.json` is available under
[Fragmented Broker/bridge service sample config](../../Fragmented%20Broker/bridge%20service%20sample%20config/).

---

## Deploy

```bash
docker stack deploy -c docker-compose.yml bridge
docker service ls
docker service logs -f bridge_bridge-service
```

---

## Configuration Notes

- **Broker URL.** Inside the Bridge configuration, point the Kafka bootstrap server at
  `kafka:9092`.
- **Domain, stream creation strategy and partition mappings** must match the ATLAS
  Stream Recorder exactly. A mismatch is not an error — the Bridge publishes happily to
  topics nothing is listening on.
- **Security.** Against an unsecured broker no `Security` block is needed. To publish to
  a secured listener, add the block for the chosen posture; the
  [Unified Broker README](../../Unified%20Broker/README.md) lists the block for each one.
  Certificates referenced there must be staged on this node too.
- **Timezone** is fixed to `Europe/London` via `TZ`.

---

## Verify

```bash
docker service ps bridge_bridge-service
docker service logs bridge_bridge-service | grep -iE "kafka|config|error"
```

A clean start means the service reaches `Running`, reports no connection errors against
`kafka:9092`, and logs the configuration it loaded from `/app/Configs`. Confirm data is
flowing by checking that topics under the configured domain appear in Kafka UI.

If the service never leaves `Pending`, the node label is the first thing to check. If it
starts but finds no configuration, confirm the two host directories exist on the Bridge
node and are not empty.
