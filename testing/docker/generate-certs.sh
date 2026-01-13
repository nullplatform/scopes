#!/bin/bash
# Generate self-signed certificates for smocker TLS

CERT_DIR="$(dirname "$0")/certs"
mkdir -p "$CERT_DIR"

# Generate private key
openssl genrsa -out "$CERT_DIR/key.pem" 2048 2>/dev/null

# Generate self-signed certificate
openssl req -new -x509 \
  -key "$CERT_DIR/key.pem" \
  -out "$CERT_DIR/cert.pem" \
  -days 365 \
  -subj "/CN=api.nullplatform.com" \
  -addext "subjectAltName=DNS:api.nullplatform.com,DNS:localhost" \
  2>/dev/null

echo "Certificates generated in $CERT_DIR"
