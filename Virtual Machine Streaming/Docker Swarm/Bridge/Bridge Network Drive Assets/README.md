# Bridge — Network Drive Assets

Deploys the **full Open Streaming stack**, with the Bridge Service reading its PGVs and
DTVs from the **shared network drive (T drive)** rather than from local disk. The share
is mounted as a CIFS volume and presented to the containers at `/tdrive`.

Because the assets are held centrally, this variant also ships the **file and config
indexer services** — they index the shared drive so the Bridge can resolve
configuration remotely instead of scanning a local directory. Kafka itself is part of
this stack, so nothing needs to be deployed beforehand.

For the local-filesystem alternative, see
[Bridge Local Assets](../Bridge%20Local%20Assets/).

---

## What Gets Deployed

| Service | Image | Published ports | Node label |
|---|---|---|---|
| `kafka` | `apache/kafka:latest` | `9094` | `role=kafka` |
| `kafka-ui` | `provectuslabs/kafka-ui:latest` | `8080` | `role=kafka` |
| `bridge-service` | `atlasplatformdocker/bridge-service-host-dev:2.1.5.3` | `9697`, `10010` | `role=bridge-service` |
| `virtual-parameter-service` | `atlasplatformdocker/virtual-parameter-service-host-dev:2.1.3.3` | `10011` → `10010` | `role=bridge-service` |
| `gateway-service` | `atlasplatformdocker/gateway-service-host-dev:0.0.0.58-ci` | `5200` (gRPC) | `role=services` |
| `file-indexer-service` | `atlasplatformdocker/file-indexing-service-dev:2.1.2.5` | `5000` | `role=services` |
| `config-indexer-service` | `atlasplatformdocker/config-indexing-service-dev:2.1.2.5` | `5050` | `role=services` |
| `mongodb` | `mongodb/mongodb-community-server:latest` | `27017` | `role=services` |
| `swagger-ui-file-indexer` | `swaggerapi/swagger-ui:latest` | `5010` → `8080` | `role=services` |
| `swagger-ui-config-indexer` | `swaggerapi/swagger-ui:latest` | `5020` → `8080` | `role=services` |

All services join the `stream_net` overlay network, which the stack creates.

---

## Prerequisites

**1. Label the Swarm nodes.** Three distinct labels are used, and any service whose
label is missing is scheduled nowhere and stays pending with no error:

```bash
docker node update --label-add role=kafka           <kafka-node>
docker node update --label-add role=bridge-service  <bridge-node>
docker node update --label-add role=services        <services-node>
```

A single node can carry more than one label if the deployment is being collapsed onto
fewer machines.

**2. CIFS support on the node running the T drive volume.** The `t_drive` volume uses
the `cifs` driver at SMB 3.0 against `//vmmcafilappp01.applied.com/Files`. The node must
be able to resolve and reach that host, and `cifs-utils` must be installed. Each service
that mounts the volume needs it available on the node it lands on — `bridge-service`,
`file-indexer-service` and `config-indexer-service`.

**3. The advertised Kafka address must match the deployment.** The broker advertises
`PLAINTEXT_HOST://10.102.40.37:9094`, so external clients such as ATLAS connect to that
address. If the Kafka node's address differs, that value has to change or external
clients will fail to connect while in-network clients keep working — a confusing
asymmetry worth ruling out first.

---

## Asset Layout on the T Drive

The share is mounted at `/tdrive` and the services expect these subdirectories:

| Path | Holds | Consumed by |
|---|---|---|
| `/tdrive/PGVs` | PGV files (`.pgv`) | Bridge, file indexer |
| `/tdrive/Config` | Config files (`.cfg`) | Bridge, file indexer |
| `/tdrive/PUL Files` | PUL files (`.pul`) | Bridge (RDA), file indexer |

The file indexer indexes exactly those three directories and those three extensions
into MongoDB; the config indexer sits in front of it, and the Bridge reaches it at
`http://config-indexer-service:5050`. Assets placed outside these paths are invisible to
the indexers even though the share as a whole is mounted.

---

## Deploy

```bash
docker stack deploy -c docker-compose.yaml bridge
docker service ls
```

MongoDB should be up before the indexers do useful work. `depends_on` is declared in the
file but **`docker stack deploy` ignores it**, so services start in arbitrary order and
the indexers may log connection errors on first boot before settling. That is expected;
persistent failure is not.

---

## Configuration Notes

- **Broker URL** is `kafka:9092` for every in-stack client, resolving over the overlay
  network.
- **`StreamCreationStrategy: 2`** is set on the Bridge, Virtual Parameter and Gateway
  services. It must match the ATLAS Stream Recorder, and must be the same across all
  three.
- **`BridgeConfig__DataSource: ADSTest01`** on the Bridge matches
  `VirtualParameterServiceConfig__DataSource` on the Virtual Parameter Service. Change
  them together.
- **`privileged: true`** is set on `bridge-service` to allow the CIFS mount inside the
  container. It is worth revisiting if the deployment is ever hardened.
- **Persistence.** Kafka logs go to `/tmp/kraft-kafka-logs` with a 10-hour retention and
  no named volume, so broker data does not survive a container replacement. MongoDB uses
  the `mongo_db_data` volume and does persist.
- **Swagger UIs** point at `10.102.40.39:5000` and `:5050` for their OpenAPI documents.
  Those addresses are hard-coded and need updating if the services node changes.

---

## Security

> **The CIFS volume definition in `docker-compose.yaml` contains a plaintext domain
> account and password**, and that file is committed to this repository. Treat the
> credential as compromised: rotate it, and move the replacement to `docker secret` or
> a CIFS credentials file mounted outside version control. Anyone with read access to
> the repository currently has read access to the file share.

Kafka in this stack is entirely unsecured — every listener is `PLAINTEXT`, and the
Virtual Parameter Service sets `StreamApiConfig__Security__Protocol: 'PLAINTEXT'`
explicitly. MongoDB is published on `27017` with no authentication configured. That is
workable for a test deployment on a trusted network and should not go further as-is; see
the [Unified Broker](../../Unified%20Broker/) for adding secured listeners without
disrupting the running plaintext ones.

---

## Verify

```bash
docker service ls
docker service logs -f bridge_bridge-service | grep -iE "kafka|tdrive|config|error"
```

Then:

- **Kafka UI** at `http://<kafka-node>:8080` — the `dev-kafka-cluster` should report
  Online, and topics under the configured domain should appear once ADS starts
  publishing.
- **File indexer** at `http://<services-node>:5010` and **config indexer** at
  `http://<services-node>:5020` — the Swagger UIs confirm both are answering and let you
  check that files from the share have actually been indexed.

If a service sits in `Pending`, check its node label. If the Bridge starts but finds no
assets, confirm the CIFS mount succeeded on the node it landed on and that the three
subdirectories exist with the exact names above — `PUL Files` contains a space.
