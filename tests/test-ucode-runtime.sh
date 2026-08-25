#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/awg3-ucode-runtime.XXXXXX")"
trap 'case "$TEST_TMP" in "${TMPDIR:-/tmp}"/awg3-ucode-runtime.*) rm -rf -- "$TEST_TMP" ;; esac' EXIT

cd "$REPOSITORY_ROOT"

if ! command -v ucode >/dev/null 2>&1; then
	if [[ "${CI:-}" == true || "${AWG3_REQUIRE_UCODE_RUNTIME:-0}" == 1 ]]; then
		echo 'ucode runtime is mandatory in CI but was not found.' >&2
		exit 1
	fi
	echo 'ucode runtime not found; exact runtime test was skipped.' >&2
	exit 0
fi

mkdir -p "${TEST_TMP}/bin"
cp amneziawg-tools/files/amneziawg3-key-helper \
	"${TEST_TMP}/bin/real-key-helper"

cat > "${TEST_TMP}/bin/awg" <<'MOCK'
#!/bin/sh
set -eu

printf '%s' "$1" >> "$AWG_ARGV_LOG"
shift
for argument do
	printf '\t%s' "$argument" >> "$AWG_ARGV_LOG"
done
printf '\n' >> "$AWG_ARGV_LOG"

make_key() {
	character="$1"
	count=0
	while [ "$count" -lt 43 ]; do
		printf '%s' "$character"
		count=$((count + 1))
	done
	printf '='
}

case "$(tail -n 1 "$AWG_ARGV_LOG" | cut -f1)" in
	genkey) make_key A ;;
	genpsk) make_key C ;;
	pubkey)
		[ "$#" -eq 0 ] || exit 90
		IFS= read -r private_key
		[ "$private_key" = "$(make_key A)" ] || exit 91
		make_key B
		;;
	*) exit 92 ;;
esac
MOCK

cat > "${TEST_TMP}/bin/uci" <<'MOCK'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$UCI_ARGV_LOG"
[ "$#" -eq 3 ]
[ "$1" = '-q' ]
[ "$2" = 'get' ]
[ "$3" = 'network.awg3.private_key' ]
count=0
while [ "$count" -lt 43 ]; do
	printf A
	count=$((count + 1))
done
printf '=\n'
MOCK

cat > "${TEST_TMP}/bin/key-helper" <<'MOCK'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$HELPER_ARGV_LOG"
exec "$REAL_KEY_HELPER" "$@"
MOCK

cat > "${TEST_TMP}/harness.uc" <<'HARNESS'
'use strict';

const plugin = loadfile(getenv('AWG3_UCODE_PLUGIN'))();
const methods = plugin['luci.amneziawg3'];

printf('%J\n', methods.generateKeyPair.call({}));
printf('%J\n', methods.generatePresharedKey.call({}));
printf('%J\n', methods.deriveStoredPublicKey.call({ args: { section: 'awg3' } }));
printf('%J\n', methods.deriveStoredPublicKey.call({ args: { section: 'bad section' } }));
HARNESS

chmod 0755 "${TEST_TMP}/bin/awg" "${TEST_TMP}/bin/uci" \
	"${TEST_TMP}/bin/key-helper" "${TEST_TMP}/bin/real-key-helper"

ucode_source=luci-proto-amneziawg3/root/usr/share/rpcd/ucode/luci.amneziawg3
sed "s|^const KEY_HELPER = .*|const KEY_HELPER = '${TEST_TMP}/bin/key-helper';|" \
	"$ucode_source" > "${TEST_TMP}/plugin.uc"

: > "${TEST_TMP}/awg.argv"
: > "${TEST_TMP}/uci.argv"
: > "${TEST_TMP}/helper.argv"

AWG3="${TEST_TMP}/bin/awg" \
UCI="${TEST_TMP}/bin/uci" \
AWG_ARGV_LOG="${TEST_TMP}/awg.argv" \
UCI_ARGV_LOG="${TEST_TMP}/uci.argv" \
HELPER_ARGV_LOG="${TEST_TMP}/helper.argv" \
REAL_KEY_HELPER="${TEST_TMP}/bin/real-key-helper" \
AWG3_UCODE_PLUGIN="${TEST_TMP}/plugin.uc" \
	ucode "${TEST_TMP}/harness.uc" > "${TEST_TMP}/output"

private_key="$(printf 'A%.0s' {1..43})="
public_key="$(printf 'B%.0s' {1..43})="
preshared_key="$(printf 'C%.0s' {1..43})="

[[ "$(wc -l < "${TEST_TMP}/output" | tr -d ' ')" == 4 ]]
if ! grep -Fxq "{ \"keys\": { \"priv\": \"${private_key}\", \"pub\": \"${public_key}\" } }" \
		"${TEST_TMP}/output"; then
	echo 'Unexpected ucode RPC output:' >&2
	sed 's/[A-Za-z0-9+\/=]\{40,\}/<redacted-test-key>/g' \
		"${TEST_TMP}/output" >&2
	exit 1
fi
grep -Fxq "{ \"key\": \"${preshared_key}\" }" "${TEST_TMP}/output"
grep -Fxq "{ \"keys\": { \"pub\": \"${public_key}\" } }" \
	"${TEST_TMP}/output"
grep -Fxq '{ "keys": { "pub": "" } }' "${TEST_TMP}/output"

grep -Eq '^--output-fd [0-9]+ generate-key-pair$' "${TEST_TMP}/helper.argv"
grep -Eq '^--output-fd [0-9]+ generate-preshared-key$' "${TEST_TMP}/helper.argv"
grep -Eq '^--output-fd [0-9]+ derive-stored-public-key awg3$' \
	"${TEST_TMP}/helper.argv"
[[ "$(wc -l < "${TEST_TMP}/helper.argv" | tr -d ' ')" == 3 ]]
grep -Fxq -- '-q get network.awg3.private_key' "${TEST_TMP}/uci.argv"

if grep -Fq "$private_key" "${TEST_TMP}/helper.argv" ||
	grep -Fq "$private_key" "${TEST_TMP}/awg.argv"; then
	echo 'Private key leaked into a helper or awg argv.' >&2
	exit 1
fi
if rg -n '\bpopen[[:space:]]*\(|/bin/sh|sh[[:space:]]+-c|shellquote' \
		"$ucode_source" >/dev/null; then
	echo 'ucode RPC contains a shell-backed command path.' >&2
	exit 1
fi

echo 'Exact ucode runtime and anonymous-pipe tests passed.'
