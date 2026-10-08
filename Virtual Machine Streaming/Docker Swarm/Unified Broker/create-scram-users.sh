#!/usr/bin/env bash
# Creates the SCRAM-SHA-256 credentials used by the SCRAMMTLS listener (:9099).
#
# Run this ON THE KAFKA NODE, after the kafka stack is up.
#
# Why this is easy here: SCRAM credentials live in KRaft cluster metadata and
# normally need an already-authenticated admin connection to create — which is
# the classic chicken-and-egg on a fully-secured broker. Because our stack keeps
# the PLAINTEXT listener on :9092, there IS an unauthenticated path in, so a
# plain kafka-configs.sh call just works. No kafka-init container, no
# --add-scram at format time, no depends_on ordering (which Swarm ignores anyway).
#
# Verified working on single-node Docker.
set -euo pipefail

BOOTSTRAP="${BOOTSTRAP:-kafka:9092}"

# Find the running Kafka container (Swarm task names are auto-generated).
CID="$(docker ps --filter "name=kafka" --filter "status=running" --format '{{.ID}} {{.Names}}' \
       | grep -v 'kafka-ui' | head -1 | cut -d' ' -f1)"

if [[ -z "$CID" ]]; then
  echo "ERROR: no running kafka container found on this node." >&2
  echo "       Are you on the node labelled role=kafka?  Try: docker ps" >&2
  exit 1
fi

echo "Using Kafka container: $CID"
echo "Bootstrap:             $BOOTSTRAP"
echo

add_user() {
  local user="$1" pass="$2"
  echo "  -> $user"
  docker exec "$CID" /opt/kafka/bin/kafka-configs.sh \
    --bootstrap-server "$BOOTSTRAP" \
    --alter \
    --add-config "SCRAM-SHA-256=[password=$pass]" \
    --entity-type users \
    --entity-name "$user"
}

echo "Creating SCRAM-SHA-256 users..."
add_user admin      admin-secret
add_user streamuser stream-secret

echo
echo "Verifying:"
docker exec "$CID" /opt/kafka/bin/kafka-configs.sh \
  --bootstrap-server "$BOOTSTRAP" \
  --describe --entity-type users

echo
echo "Done. The SCRAMMTLS listener (kafka:9099) will now accept these users."
