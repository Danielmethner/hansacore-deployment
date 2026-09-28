#!/bin/bash
# Local DEV TLS setup: a private Root CA, a server certificate for the DEV
# hostnames signed by it, a Java truststore holding the CA, and the
# hansacore-tls / hansacore-ca-trust Secrets. Run inside the VM (needs kubectl).
#
# The CA is created only once and reused on later runs, so browsers that
# already trust ssl/ca.crt and the Java truststore stay valid. Delete
# ca.key/ca.crt to force a new CA (then re-import it on Windows, see README).
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ENV_FILE="$DIR/../k8s/overlays/local-vm/hansacore-env.properties"
cd "$DIR"

# tr strips CR so a properties file saved with Windows line endings still works.
get_val() { grep -m1 "^$1=" "$ENV_FILE" | cut -d= -f2- | tr -d '\r'; }
ERP_HOSTNAME="$(get_val ERP_HOSTNAME)"
PORTAL_HOSTNAME="$(get_val PORTAL_HOSTNAME)"
AUTH_HOSTNAME="$(get_val AUTH_HOSTNAME)"
if [ -z "$ERP_HOSTNAME" ] || [ -z "$PORTAL_HOSTNAME" ] || [ -z "$AUTH_HOSTNAME" ]; then
  echo "ERP_HOSTNAME, PORTAL_HOSTNAME and AUTH_HOSTNAME must be set in $ENV_FILE" >&2
  exit 1
fi

NEW_CA=0
if [ -f ca.key ] && [ -f ca.crt ]; then
  echo "=== 1. Reusing existing Root CA ($(openssl x509 -in ca.crt -noout -subject)) ==="
else
  NEW_CA=1
  echo "=== 1. Generating Root CA ==="
  openssl genrsa -out ca.key 4096
  openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
    -subj "/C=CH/ST=Zurich/O=HansaCore/CN=HansaCore Root CA" \
    -out ca.crt
fi

CURRENT_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
echo "Detected current VM IP: ${CURRENT_IP}"

# k3s-lab.mshome.net is kept only for the transition away from the old
# single-host layout.
ALT_NAMES="[alt_names]
DNS.1 = ${ERP_HOSTNAME}
DNS.2 = ${PORTAL_HOSTNAME}
DNS.3 = ${AUTH_HOSTNAME}
DNS.4 = k3s-lab.mshome.net
DNS.5 = localhost
IP.1 = 127.0.0.1"
if [ -n "$CURRENT_IP" ]; then
  ALT_NAMES="${ALT_NAMES}
IP.2 = ${CURRENT_IP}"
fi

echo "=== 2. Generating Server Key & CSR ==="
openssl genrsa -out server.key 2048

cat > csr.conf <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[dn]
C = CH
ST = Zurich
O = HansaCore
CN = ${ERP_HOSTNAME}

[req_ext]
subjectAltName = @alt_names

${ALT_NAMES}
EOF

openssl req -new -key server.key -out server.csr -config csr.conf

cat > cert.conf <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

${ALT_NAMES}
EOF

echo "=== 3. Signing Server Certificate with Root CA ==="
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days 825 -sha256 -extfile cert.conf

# Bundle server cert + CA cert
cat server.crt ca.crt > tls.crt

echo "=== 4. Java Truststore (truststore.p12) ==="

# Random per-VM password instead of the well-known "changeit" default. Note
# this truststore only ever holds the CA's *public* certificate (no private
# key material), so this isn't protecting a secret — it's just avoiding a
# well-known-default finding in security scans. Persisted alongside the
# other generated (git-ignored) TLS artifacts so re-runs stay idempotent.
if [ -f truststore-password.txt ]; then
  TRUSTSTORE_PASSWORD="$(cat truststore-password.txt)"
else
  TRUSTSTORE_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-24)"
  echo -n "$TRUSTSTORE_PASSWORD" > truststore-password.txt
  chmod 600 truststore-password.txt
fi

# The truststore only holds the CA, so it is rebuilt only when the CA changed.
if [ "$NEW_CA" = "0" ] && [ -f truststore.p12 ]; then
  echo "CA unchanged, keeping existing truststore.p12"
elif command -v keytool >/dev/null 2>&1; then
  rm -f truststore.p12
  keytool -importcert -noprompt -alias hansacore-ca -file ca.crt \
    -keystore truststore.p12 -storepass "$TRUSTSTORE_PASSWORD" -storetype PKCS12
else
  rm -f truststore.p12
  kubectl run keytool-gen --rm -i --restart=Never \
    --image=eclipse-temurin:21-jre-alpine \
    -- /bin/sh -c "cat > /tmp/ca.crt && keytool -importcert -noprompt -alias hansacore-ca -file /tmp/ca.crt -keystore /tmp/truststore.p12 -storepass '$TRUSTSTORE_PASSWORD' -storetype PKCS12 && cat /tmp/truststore.p12" < ca.crt > truststore.p12
fi

echo "=== 5. Creating / Updating Kubernetes Secrets ==="
kubectl create secret tls hansacore-tls \
  --cert=tls.crt \
  --key=server.key \
  -n hansacore \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic hansacore-ca-trust \
  --from-file=truststore.p12=truststore.p12 \
  --from-file=ca.crt=ca.crt \
  --from-literal=TRUSTSTORE_PASSWORD="$TRUSTSTORE_PASSWORD" \
  -n hansacore \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== Local SSL setup complete! ==="
