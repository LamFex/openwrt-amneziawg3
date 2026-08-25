#!/bin/sh
# shellcheck disable=SC3043
set -eu

GO_VERSION=3.1.20260814
GO_HASH=c146a640c18468caac71fd158c02a94afcf6beadb5fd585c092bf55cbdefdbff
TOOLS_VERSION=3.1.20260812
TOOLS_HASH=dbd8ce0748d835d18f30bb76720246b7bfc80bd09cd17c379b1c59f683a18493

VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/awg3-upstream.XXXXXX")"
trap 'case "$VERIFY_DIR" in "${TMPDIR:-/tmp}"/awg3-upstream.*) rm -rf -- "$VERIFY_DIR" ;; esac' EXIT

download() {
	local url="$1"
	local output="$2"

	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url" -o "$output"
	else
		wget -qO "$output" "$url"
	fi
}

hash_file() {
	local file="$1"

	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file" | awk '{ print $1 }'
	else
		shasum -a 256 "$file" | awk '{ print $1 }'
	fi
}

verify_archive() {
	local name="$1"
	local version="$2"
	local expected="$3"
	local output="${VERIFY_DIR}/${name}.tar.gz"
	local actual

	download \
		"https://codeload.github.com/amnezia-vpn/${name}/tar.gz/refs/tags/v${version}" \
		"$output"
	actual="$(hash_file "$output")"
	if [ "$actual" != "$expected" ]; then
		echo "${name} v${version}: expected ${expected}, got ${actual}" >&2
		exit 1
	fi
	printf '%s\n' "${name} v${version}: ${actual}"
}

verify_archive amneziawg-go "$GO_VERSION" "$GO_HASH"
verify_archive amneziawg-tools "$TOOLS_VERSION" "$TOOLS_HASH"

tar -xzf "${VERIFY_DIR}/amneziawg-go.tar.gz" -C "$VERIFY_DIR" \
	"amneziawg-go-${GO_VERSION}/Dockerfile"
grep -Fq "ARG AWGTOOLS_COMMIT=\"v${TOOLS_VERSION}\"" \
	"${VERIFY_DIR}/amneziawg-go-${GO_VERSION}/Dockerfile" || {
	echo "amneziawg-go ${GO_VERSION} does not pin tools ${TOOLS_VERSION}." >&2
	exit 1
}
echo "amneziawg-go Dockerfile pins matching tools v${TOOLS_VERSION}."
