#!/usr/bin/env bash
# Generates a local CA plus a broker keystore/truststore (PKCS12 format) for
# the SASL_SSL example. Re-run any time to regenerate fresh certs.
#
# PKCS12 is used (instead of PEM) because the apache/kafka Docker image's
# configure script requires a keystore filename + credentials-file pair
# (KAFKA_SSL_KEYSTORE_FILENAME / KAFKA_SSL_KEYSTORE_CREDENTIALS /
# KAFKA_SSL_KEY_CREDENTIALS). Requires openssl and docker (docker is used to
# run keytool from the apache/kafka image itself, so no host JDK is needed).
set -euo pipefail

# Prevent Git Bash on Windows from rewriting "/CN=..." subject args as file paths.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

DAYS=3650
PASSWORD="${CERT_PASSWORD:-changeit}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/secrets"

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

echo "Generating CA..."
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days "$DAYS" \
  -subj "/CN=kafka-example-ca" -out ca.crt

echo "Generating broker key + CSR..."
openssl genrsa -out kafka.key 2048
openssl req -new -key kafka.key -subj "/CN=kafka" -out kafka.csr

cat > kafka.ext <<EOF
subjectAltName = DNS:kafka,DNS:localhost,IP:127.0.0.1
extendedKeyUsage = serverAuth,clientAuth
EOF

echo "Signing broker certificate with CA..."
openssl x509 -req -in kafka.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out kafka.crt -days "$DAYS" -sha256 -extfile kafka.ext

echo "Building PKCS12 keystore (broker key + cert + CA chain)..."
openssl pkcs12 -export \
  -in kafka.crt -inkey kafka.key -certfile ca.crt \
  -name kafka -out kafka.keystore.p12 \
  -passout "pass:$PASSWORD"

echo "Building PKCS12 truststore (CA cert only)..."
# openssl's "pkcs12 -export -nokeys" produces a certificate bag that Java's
# PKCS12 provider doesn't load as a trusted entry, so use keytool (via the
# broker image itself) to build the truststore instead.
rm -f kafka.truststore.p12
docker run --rm -v "$OUT_DIR:/certs" --entrypoint keytool apache/kafka:latest \
  -importcert -noprompt -alias kafka-example-ca \
  -file /certs/ca.crt \
  -keystore /certs/kafka.truststore.p12 \
  -storetype PKCS12 \
  -storepass "$PASSWORD"

# Credential files read by the apache/kafka image's configure script.
# PKCS12 requires the key password to match the keystore password.
printf '%s' "$PASSWORD" > kafka_keystore_creds
printf '%s' "$PASSWORD" > kafka_key_creds
printf '%s' "$PASSWORD" > kafka_truststore_creds

rm -f kafka.csr kafka.ext ca.srl

echo "Done. Certs written to $OUT_DIR (password: $PASSWORD)"
