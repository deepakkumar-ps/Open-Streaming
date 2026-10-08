#!/usr/bin/env bash
# Generates every certificate/keystore the multi-listener secured Kafka stack
# needs, plus the client material for the Bridge / VPS / Gateway services.
#
#   ca.crt / ca.key              the local CA. ca.crt is what clients trust.
#   kafka.keystore.p12           broker identity (all TLS listeners share it)
#   kafka.truststore.p12         CA, used to validate client certs (mTLS listeners)
#   kafka_*_creds                password files (kept for compatibility)
#   client.crt / client.key      PEM client cert for librdkafka clients
#                                (Bridge Service, VPS, Gateway)
#   kafka-ui.keystore.p12        PKCS12 client cert for kafka-ui (Java)
#
# Requires openssl and docker (docker runs keytool from the apache/kafka image,
# so no host JDK is needed). Safe to re-run — regenerates everything.
#
# The broker SAN must cover EVERY hostname/IP a TLS client uses to reach Kafka,
# or hostname verification fails. Defaults below cover the in-swarm name
# (kafka), localhost, and the Kafka node's IP. Add more via EXTRA_SANS.
#
#   EXTRA_SANS="DNS:kafka.internal,IP:10.104.10.90" ./generate-certs.sh
set -euo pipefail

# Prevent Git Bash on Windows from rewriting "/CN=..." subject args as paths.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

DAYS=3650
PASSWORD="${CERT_PASSWORD:-changeit}"
KAFKA_NODE_IP="${KAFKA_NODE_IP:-10.104.10.89}"
BASE_SANS="DNS:kafka,DNS:localhost,IP:127.0.0.1,IP:${KAFKA_NODE_IP}"
SANS="${BASE_SANS}${EXTRA_SANS:+,$EXTRA_SANS}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/secrets"

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

echo "Broker certificate SAN: $SANS"
echo

echo "[1/5] Generating CA..."
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days "$DAYS" \
  -subj "/CN=kafka-security-test-ca" -out ca.crt

echo "[2/5] Generating broker certificate..."
openssl genrsa -out kafka.key 2048
openssl req -new -key kafka.key -subj "/CN=kafka" -out kafka.csr
cat > kafka.ext <<EOF
subjectAltName = $SANS
extendedKeyUsage = serverAuth,clientAuth
EOF
openssl x509 -req -in kafka.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out kafka.crt -days "$DAYS" -sha256 -extfile kafka.ext

echo "[3/5] Building broker PKCS12 keystore..."
openssl pkcs12 -export \
  -in kafka.crt -inkey kafka.key -certfile ca.crt \
  -name kafka -out kafka.keystore.p12 \
  -passout "pass:$PASSWORD"

echo "[4/5] Building PKCS12 truststore (CA only)..."
# openssl's "pkcs12 -export -nokeys" produces a certificate bag that Java's
# PKCS12 provider will not load as a *trusted* entry, so build the truststore
# with keytool (run from the broker image itself) instead.
rm -f kafka.truststore.p12
docker run --rm -v "$OUT_DIR:/certs" --entrypoint keytool apache/kafka:latest \
  -importcert -noprompt -alias kafka-security-test-ca \
  -file /certs/ca.crt \
  -keystore /certs/kafka.truststore.p12 \
  -storetype PKCS12 \
  -storepass "$PASSWORD"

make_client_cert() {
  local name="$1"
  echo "      client certificate: $name"
  openssl genrsa -out "$name.key" 2048
  openssl req -new -key "$name.key" -subj "/CN=$name" -out "$name.csr"
  cat > "$name.ext" <<EOF
extendedKeyUsage = clientAuth
EOF
  openssl x509 -req -in "$name.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out "$name.crt" -days "$DAYS" -sha256 -extfile "$name.ext"
  rm -f "$name.csr" "$name.ext"
}

echo "[5/5] Generating client certificates..."
# PEM pair for librdkafka clients (Bridge Service, VPS, Gateway)
make_client_cert client
# PKCS12 for kafka-ui (Java client)
make_client_cert kafka-ui
openssl pkcs12 -export \
  -in kafka-ui.crt -inkey kafka-ui.key -certfile ca.crt \
  -name kafka-ui -out kafka-ui.keystore.p12 \
  -passout "pass:$PASSWORD"

printf '%s' "$PASSWORD" > kafka_keystore_creds
printf '%s' "$PASSWORD" > kafka_key_creds
printf '%s' "$PASSWORD" > kafka_truststore_creds

# The broker JAAS entry is version-controlled (it holds no secrets), but the
# broker expects it alongside the certs, so copy it into secrets/ here. That
# keeps deployment to a single "scp -r secrets" of one self-contained folder.
cp "$SCRIPT_DIR/kafka_server_jaas.conf" "$OUT_DIR/kafka_server_jaas.conf"

rm -f kafka.csr kafka.ext ca.srl

echo
echo "Done. Written to $OUT_DIR (store password: $PASSWORD)"
echo
echo "Verify the SAN took effect:"
echo "  openssl x509 -in $OUT_DIR/kafka.crt -noout -text | grep -A1 'Subject Alternative Name'"
