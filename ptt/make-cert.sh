#!/bin/bash
# One-time: create a self-signed code-signing identity named "Pardon" in the login
# keychain, so rebuilds of Pardon.app keep their Microphone and Accessibility grants
# (macOS ties those grants to the signing certificate; ad-hoc builds lose them).
#
#   - idempotent: does nothing if the identity already exists
#   - the certificate is NOT marked trusted for anything (no add-trusted-cert)
#   - codesign is explicitly allowed to use the key (-T /usr/bin/codesign); the key is not extractable (-x)
#
#   KEYCHAIN   target keychain (default ~/Library/Keychains/login.keychain-db)
#   OPENSSL    openssl binary (default /usr/bin/openssl)
#
# Run from anywhere:  ./ptt/make-cert.sh   (or: make ptt-cert)
set -euo pipefail
cd "$(dirname "$0")"
umask 077

NAME="Pardon"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
OPENSSL="${OPENSSL:-/usr/bin/openssl}"
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "needs macOS"
# No -v: an untrusted self-signed identity is listed only without it.
ids="$(/usr/bin/security find-identity -p codesigning "$KEYCHAIN" || true)"
if grep -q "\"$NAME\"" <<<"$ids"; then
  ok "code-signing identity \"$NAME\" already exists — nothing to do"
  exit 0
fi

echo "Creating a self-signed code-signing identity \"$NAME\" in $KEYCHAIN"
tmp="$(mktemp -d -t pardon-cert)"
chmod 700 "$tmp"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/req.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF

if ! "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/req.cnf" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>"$tmp/openssl.log"; then
  cat "$tmp/openssl.log" >&2
  die "openssl could not create the certificate"
fi
# Throwaway passphrase: protects the .p12 only for the seconds it exists in $tmp.
PARDON_P12_PASS="$("$OPENSSL" rand -hex 16)"
export PARDON_P12_PASS
"$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -out "$tmp/pardon.p12" -passout env:PARDON_P12_PASS
/usr/bin/security import "$tmp/pardon.p12" -k "$KEYCHAIN" -f pkcs12 -P "$PARDON_P12_PASS" -x -T /usr/bin/codesign >/dev/null
unset PARDON_P12_PASS

ok "created code-signing identity \"$NAME\" in $KEYCHAIN (valid 10 years)"
echo "    It is used for nothing but signing Pardon.app; it is not trusted for TLS or anything else."
echo "    When macOS asks whether codesign may use the \"Pardon\" key (it may also ask for your login"
echo "    keychain password), choose Allow: macOS should then ask again on later builds, which keeps"
echo "    any use of the key visible to you. Always Allow removes the prompt and lets any program running"
echo "    as you sign with the key silently."
echo "    To remove it: Keychain Access → login → My Certificates → Pardon → delete."
