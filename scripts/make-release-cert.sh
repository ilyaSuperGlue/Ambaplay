#!/bin/sh
# One-time setup for whoever publishes Ambaplay releases: create the self-signed
# "Ambaplay Release" code-signing identity in the login keychain and write a .p12
# backup of it. Releases signed with the same identity keep the same designated
# requirement, so macOS permissions such as App Management survive updates.
# Losing the identity means every user grants those permissions once more.
#
# Usage: scripts/make-release-cert.sh [backup.p12]
# Env:   AMBAPLAY_SIGN_IDENTITY  identity name (default "Ambaplay Release")
#        KEYCHAIN                  keychain to import into (default: login keychain)
#        BP_P12_PASS               backup password; asked for when unset
set -eu

name=${AMBAPLAY_SIGN_IDENTITY:-Ambaplay Release}
out=${1:-"$HOME/Desktop/$(printf '%s' "$name" | tr ' ' '-').p12"}
keychain=${KEYCHAIN:-"$HOME/Library/Keychains/login.keychain-db"}

die() { printf 'make-release-cert: %s\n' "$*" >&2; exit 1; }

if security find-identity -p codesigning "$keychain" | grep -q "\"$name\""; then
	printf '"%s" is already in %s; nothing to do.\n' "$name" "$keychain"
	exit 0
fi
[ -e "$out" ] && die "$out already exists; move it or pass another path"

if [ -z "${BP_P12_PASS:-}" ]; then
	[ -t 0 ] || die "set BP_P12_PASS or run this in a terminal"
	printf 'Password for the backup (keep it in your password manager): '
	stty -echo; read -r BP_P12_PASS; stty echo; printf '\n'
	printf 'Again: '
	stty -echo; read -r again; stty echo; printf '\n'
	[ "$BP_P12_PASS" = "$again" ] || die "the passwords do not match"
fi
[ ${#BP_P12_PASS} -ge 12 ] || die "use a password of at least 12 characters"
export BP_P12_PASS

# The private key exists in plain text only inside this folder, removed on exit.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
umask 077

openssl req -x509 -newkey rsa:3072 -nodes -days 7300 -subj "/CN=$name" \
	-addext "keyUsage=critical,digitalSignature" \
	-addext "extendedKeyUsage=critical,codeSigning" \
	-addext "basicConstraints=critical,CA:false" \
	-keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null || die "openssl could not create the certificate"

# OpenSSL 3 and later write a .p12 the keychain cannot read unless -legacy is given;
# LibreSSL has no -legacy and already writes the old format.
openssl pkcs12 -export -legacy -name "$name" -inkey "$work/key.pem" -in "$work/cert.pem" \
	-passout env:BP_P12_PASS -out "$out" 2>/dev/null \
	|| openssl pkcs12 -export -name "$name" -inkey "$work/key.pem" -in "$work/cert.pem" \
		-passout env:BP_P12_PASS -out "$out" \
	|| die "openssl could not write $out"

security import "$out" -k "$keychain" -P "$BP_P12_PASS" -T /usr/bin/codesign >/dev/null \
	|| die "could not import the identity into $keychain"

security find-identity -p codesigning "$keychain" | grep "\"$name\"" \
	|| die "the identity was imported but codesign cannot see it"

cat <<EOF

Done. "$name" is in your keychain and backed up to:
  $out
Move that file and its password into your password manager, then delete it here.
The first build signed with it asks for access to the key: choose Always Allow.
EOF
