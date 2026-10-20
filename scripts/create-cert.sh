#!/usr/bin/env bash
# Creates a self-signed code signing certificate in the login keychain and lets codesign
# use its key without prompting. A stable signing identity keeps the Accessibility
# permission across rebuilds. Safe to run again.
set -euo pipefail

IDENTITY="${PISMO_SIGN_IDENTITY:-Pismo Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

main() {
  if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Certificate \"$IDENTITY\" already exists in the login keychain."
  else
    create_and_import_certificate
  fi

  allow_codesign_key_access

  echo "Done:"
  security find-identity -p codesigning "$KEYCHAIN" | grep "\"$IDENTITY\"" || {
    echo "Error: \"$IDENTITY\" is not available as a code signing identity." >&2
    exit 1
  }
}

WORK_DIR=""
cleanup() {
  if [[ -n "$WORK_DIR" ]]; then rm -rf "$WORK_DIR"; fi
}
trap cleanup EXIT

create_and_import_certificate() {
  WORK_DIR="$(mktemp -d)"
  local work_dir="$WORK_DIR"

  cat >"$work_dir/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no

[dn]
CN = $IDENTITY

[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

  echo "Generating certificate \"$IDENTITY\"…"
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$work_dir/cert.cnf" \
    -keyout "$work_dir/key.pem" \
    -out "$work_dir/cert.pem" 2>/dev/null

  local p12_password
  p12_password="$(openssl rand -hex 16)"
  openssl pkcs12 -export \
    -inkey "$work_dir/key.pem" \
    -in "$work_dir/cert.pem" \
    -name "$IDENTITY" \
    -out "$work_dir/cert.p12" \
    -passout "pass:$p12_password"

  echo "Importing into the login keychain…"
  security import "$work_dir/cert.p12" -k "$KEYCHAIN" -P "$p12_password" -T /usr/bin/codesign
}

allow_codesign_key_access() {
  echo "Allowing codesign to use the key without prompting."
  echo "Enter your login (Mac) password when asked:"
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$IDENTITY" "$KEYCHAIN" >/dev/null
}

main "$@"
