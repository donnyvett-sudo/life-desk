#!/bin/zsh
# Creates a local code-signing identity "Life Desk Local" in the login keychain (once).
# Why: with an ad-hoc signature every rebuild looks like a different app, so a Keychain item made by an earlier
# build asks for the login password again. A stable identity keeps the item readable without prompts.
# The certificate is self-signed and only for this Mac; it is not trusted by anyone else.
set -euo pipefail
NAME="Life Desk Local"
KC="$HOME/Library/Keychains/login.keychain-db"
if security find-identity -p codesigning "$KC" 2>/dev/null | grep -q "\"$NAME\""; then
  echo "Identity \"$NAME\" already exists."; exit 0
fi
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
cat > "$D/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$D/key.pem" -out "$D/cert.pem" -config "$D/cert.cnf" 2>/dev/null
PW="$(openssl rand -hex 16)"
openssl pkcs12 -export -inkey "$D/key.pem" -in "$D/cert.pem" -name "$NAME" -out "$D/id.p12" -passout "pass:$PW" 2>/dev/null
security import "$D/id.p12" -k "$KC" -P "$PW" -T /usr/bin/codesign
# Prove it works on a throwaway binary.
cp /usr/bin/true "$D/probe"
if codesign --force --sign "$NAME" "$D/probe" 2>"$D/err"; then
  echo "OK: \"$NAME\" can sign. The first build may ask once whether codesign may use the key: choose Always Allow."
else
  echo "Imported, but signing failed: $(cat "$D/err")"; exit 1
fi
