#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$DIR"

echo "=== 1. Generating Root CA ==="
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
  -subj "/C=CH/ST=Zurich/O=HansaCore/CN=HansaCore Root CA" \
  -out ca.crt

CURRENT_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || hostname -I | awk '{print $1}')
echo "Detected current VM IP: ${CURRENT_IP}"

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
CN = ${CURRENT_IP}

[req_ext]
subjectAltName = @alt_names

[alt_names]
IP.1 = ${CURRENT_IP}
IP.2 = 172.19.148.154
IP.3 = 172.22.132.198
IP.4 = 127.0.0.1
DNS.1 = localhost
DNS.2 = k3s-lab.mshome.net
DNS.3 = hansacore.local
DNS.4 = *.mshome.net
EOF

openssl req -new -key server.key -out server.csr -config csr.conf

cat > cert.conf <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
IP.1 = ${CURRENT_IP}
IP.2 = 172.19.148.154
IP.3 = 172.22.132.198
IP.4 = 127.0.0.1
DNS.1 = localhost
DNS.2 = k3s-lab.mshome.net
DNS.3 = hansacore.local
DNS.4 = *.mshome.net
EOF

echo "=== 3. Signing Server Certificate with Root CA ==="
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days 825 -sha256 -extfile cert.conf

# Bundle server cert + CA cert
cat server.crt ca.crt > tls.crt

echo "=== 4. Creating Java Truststore (truststore.p12) ==="
rm -f truststore.p12

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

if command -v keytool >/dev/null 2>&1; then
  keytool -importcert -noprompt -alias hansacore-ca -file ca.crt \
    -keystore truststore.p12 -storepass "$TRUSTSTORE_PASSWORD" -storetype PKCS12
else
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
