#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/awg3-key-helper.XXXXXX")"
trap 'case "$TEST_TMP" in "${TMPDIR:-/tmp}"/awg3-key-helper.*) rm -rf -- "$TEST_TMP" ;; esac' EXIT

cd "$REPOSITORY_ROOT"
mkdir -p "${TEST_TMP}/bin"

cat > "${TEST_TMP}/bin/awg" <<'MOCK'
#!/bin/sh
set -eu
printf '%s' "$1" >> "$AWG_MOCK_LOG"
shift
for argument do
	printf '\t%s' "$argument" >> "$AWG_MOCK_LOG"
done
printf '\n' >> "$AWG_MOCK_LOG"

make_key() {
	character="$1"
	count=0
	while [ "$count" -lt 43 ]; do
		printf '%s' "$character"
		count=$((count + 1))
	done
	printf '='
}

case "${1:-}" in
	'') ;;
esac

case "$(tail -n 1 "$AWG_MOCK_LOG" | cut -f1)" in
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
printf '%s\n' "$*" >> "$UCI_MOCK_LOG"
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

chmod 0755 "${TEST_TMP}/bin/awg" "${TEST_TMP}/bin/uci"
: > "${TEST_TMP}/awg.argv"
: > "${TEST_TMP}/uci.argv"

export AWG_MOCK_LOG="${TEST_TMP}/awg.argv"
export UCI_MOCK_LOG="${TEST_TMP}/uci.argv"
helper=amneziawg-tools/files/amneziawg3-key-helper

pair="$(AWG3="${TEST_TMP}/bin/awg" UCI="${TEST_TMP}/bin/uci" \
	sh "$helper" generate-key-pair)"
private_key="$(printf '%s\n' "$pair" | sed -n '1p')"
public_key="$(printf '%s\n' "$pair" | sed -n '2p')"
[[ "${#private_key}" -eq 44 && "${#public_key}" -eq 44 ]]
[[ "$(wc -l < "${TEST_TMP}/awg.argv" | tr -d ' ')" == 2 ]]
grep -Fxq 'genkey' "${TEST_TMP}/awg.argv"
grep -Fxq 'pubkey' "${TEST_TMP}/awg.argv"
if grep -Fq "$private_key" "${TEST_TMP}/awg.argv"; then
	echo 'Private key leaked into the awg argv log.' >&2
	exit 1
fi

psk="$(AWG3="${TEST_TMP}/bin/awg" UCI="${TEST_TMP}/bin/uci" \
	sh "$helper" generate-preshared-key)"
[[ "${#psk}" -eq 44 ]]

derived="$(AWG3="${TEST_TMP}/bin/awg" UCI="${TEST_TMP}/bin/uci" \
	sh "$helper" derive-stored-public-key awg3)"
[[ "$derived" == "$public_key" ]]
grep -Fxq -- '-q get network.awg3.private_key' "${TEST_TMP}/uci.argv"

uci_calls_before="$(wc -l < "${TEST_TMP}/uci.argv" | tr -d ' ')"
if AWG3="${TEST_TMP}/bin/awg" UCI="${TEST_TMP}/bin/uci" \
	sh "$helper" derive-stored-public-key 'bad section' >/dev/null 2>&1; then
	echo 'Unsafe UCI section name was accepted.' >&2
	exit 1
fi
uci_calls_after="$(wc -l < "${TEST_TMP}/uci.argv" | tr -d ' ')"
[[ "$uci_calls_before" == "$uci_calls_after" ]]

if rg -n 'set[[:space:]]+-x|logger|mktemp|/tmp/|sh[[:space:]]+-c' "$helper" >/dev/null; then
	echo 'Key helper contains a logging, temporary-file, or shell-evaluation path.' >&2
	exit 1
fi
echo 'Key-helper secrecy tests passed.'
