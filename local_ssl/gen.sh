#!/bin/bash
set -e

# Directory where the script is located
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Generating certificates in $DIR"

# 1. Generate local CA
openssl genrsa -out "$DIR/localCA.key" 4096
openssl req -x509 -new -nodes -key "$DIR/localCA.key" -sha256 -days 3650 -out "$DIR/localCA.crt" -subj "/CN=Local Dev CA"

# 2. Generate server key
openssl ecparam -genkey -name prime256v1 -out "$DIR/localhost.key"

# 3. Create CSR
openssl req -new -key "$DIR/localhost.key" -out "$DIR/localhost.csr" -subj "/CN=localhost"

# 4. Create extension file for SAN
cat > "$DIR/localhost.ext" <<EOF
subjectAltName = DNS:localhost
EOF

# 5. Sign server certificate with local CA
openssl x509 -req -in "$DIR/localhost.csr" -CA "$DIR/localCA.crt" -CAkey "$DIR/localCA.key" -CAcreateserial \
    -out "$DIR/localhost.crt" -days 365 -sha256 -extfile "$DIR/localhost.ext"

echo "Done! Files generated:"
echo "  Local CA: $DIR/localCA.crt (trust this in browser)"
echo "  Server cert: $DIR/localhost.crt"
echo "  Server key: $DIR/localhost.key"
