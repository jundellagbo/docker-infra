#!/bin/bash

# Generate self-signed wildcard SSL certificates for *.dev.local
# These certificates will work for any subdomain: app.dev.local, api.dev.local, etc.

set -e

SSL_DIR="$(dirname "$0")/../ssl"
DOMAIN="dev.local"

mkdir -p "$SSL_DIR"

echo "Generating wildcard SSL certificate for *.${DOMAIN}..."
echo ""

# Generate CA key and certificate
openssl genrsa -out "$SSL_DIR/ca.key" 4096

openssl req -x509 -new -nodes \
    -key "$SSL_DIR/ca.key" \
    -sha256 -days 3650 \
    -out "$SSL_DIR/ca.crt" \
    -subj "/C=US/ST=Dev/L=Local/O=DevLocal/CN=Dev Local CA"

# Create config for wildcard certificate
cat > "$SSL_DIR/wildcard.cnf" << EOF
[req]
default_bits = 2048
distinguished_name = req_distinguished_name
req_extensions = req_ext
x509_extensions = v3_ca

[req_distinguished_name]
countryName = Country Name
stateOrProvinceName = State
localityName = City
organizationName = Organization
commonName = Common Name

[req_ext]
subjectAltName = @alt_names

[v3_ca]
subjectAltName = @alt_names
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature, keyEncipherment

[alt_names]
DNS.1 = *.${DOMAIN}
DNS.2 = ${DOMAIN}
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF

# Generate wildcard certificate key and CSR
openssl genrsa -out "$SSL_DIR/wildcard.key" 2048

openssl req -new \
    -key "$SSL_DIR/wildcard.key" \
    -out "$SSL_DIR/wildcard.csr" \
    -subj "/C=US/ST=Dev/L=Local/O=DevLocal/CN=*.${DOMAIN}" \
    -config "$SSL_DIR/wildcard.cnf"

# Sign the certificate with our CA
openssl x509 -req \
    -in "$SSL_DIR/wildcard.csr" \
    -CA "$SSL_DIR/ca.crt" \
    -CAkey "$SSL_DIR/ca.key" \
    -CAcreateserial \
    -out "$SSL_DIR/wildcard.crt" \
    -days 3650 \
    -sha256 \
    -extensions v3_ca \
    -extfile "$SSL_DIR/wildcard.cnf"

# Set permissions
chmod 600 "$SSL_DIR"/*.key
chmod 644 "$SSL_DIR"/*.crt

echo ""
echo "=========================================="
echo " SSL certificates generated successfully!"
echo "=========================================="
echo ""
echo "Files created in: $SSL_DIR"
echo "  - ca.crt          (CA certificate - install this in your browser/OS)"
echo "  - ca.key          (CA private key)"
echo "  - wildcard.crt    (Wildcard certificate for *.dev.local)"
echo "  - wildcard.key    (Wildcard private key)"
echo ""
echo "=========================================="
echo " INSTALL CA CERTIFICATE IN WINDOWS"
echo "=========================================="
echo ""
echo "The ca.crt file is located at:"
echo "  WSL path: $SSL_DIR/ca.crt"
echo ""
echo "To find Windows path, run:"
echo "  wslpath -w $SSL_DIR/ca.crt"
echo ""
echo "Installation steps:"
echo "  1. Open Windows File Explorer and navigate to the ssl folder"
echo "     (\\\\wsl$\\Ubuntu\\home\\jundell\\infra\\ssl or similar)"
echo "  2. Double-click on 'ca.crt'"
echo "  3. Click 'Install Certificate...'"
echo "  4. Select 'Local Machine' and click Next"
echo "  5. Select 'Place all certificates in the following store'"
echo "  6. Click 'Browse' and select 'Trusted Root Certification Authorities'"
echo "  7. Click Next, then Finish"
echo "  8. Restart your browser"
echo ""
echo "Alternative: PowerShell (Run as Administrator):"
echo "  Import-Certificate -FilePath \"\\\\wsl\$\\Ubuntu\\home\\jundell\\infra\\ssl\\ca.crt\" -CertStoreLocation Cert:\\LocalMachine\\Root"
echo ""
echo "=========================================="
