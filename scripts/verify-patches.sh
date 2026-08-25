#!/bin/sh
# shellcheck disable=SC3043
set -eu

REPOSITORY_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/awg3-patches.XXXXXX")"
trap 'case "$VERIFY_DIR" in "${TMPDIR:-/tmp}"/awg3-patches.*) rm -rf -- "$VERIFY_DIR" ;; esac' EXIT

download() {
	local url="$1"
	local output="$2"

	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url" -o "$output"
	else
		wget -qO "$output" "$url"
	fi
}

download \
	https://codeload.github.com/amnezia-vpn/amneziawg-go/tar.gz/refs/tags/v3.1.20260814 \
	"${VERIFY_DIR}/go.tar.gz"
download \
	https://codeload.github.com/amnezia-vpn/amneziawg-tools/tar.gz/refs/tags/v3.1.20260812 \
	"${VERIFY_DIR}/tools.tar.gz"

tar -xzf "${VERIFY_DIR}/go.tar.gz" -C "$VERIFY_DIR"
tar -xzf "${VERIFY_DIR}/tools.tar.gz" -C "$VERIFY_DIR"

patch --dry-run -p1 \
	-d "${VERIFY_DIR}/amneziawg-go-3.1.20260814" \
	< "${REPOSITORY_ROOT}/amneziawg-go/patches/010-version-variable.patch"
patch --dry-run -p1 \
	-d "${VERIFY_DIR}/amneziawg-tools-3.1.20260812" \
	< "${REPOSITORY_ROOT}/amneziawg-tools/patches/020-openwrt-userspace-only.patch"

patch -p1 \
	-d "${VERIFY_DIR}/amneziawg-go-3.1.20260814" \
	< "${REPOSITORY_ROOT}/amneziawg-go/patches/010-version-variable.patch"
patch -p1 \
	-d "${VERIFY_DIR}/amneziawg-tools-3.1.20260812" \
	< "${REPOSITORY_ROOT}/amneziawg-tools/patches/020-openwrt-userspace-only.patch"

grep -Fq 'var Version' \
	"${VERIFY_DIR}/amneziawg-go-3.1.20260814/version.go"
bash -n \
	"${VERIFY_DIR}/amneziawg-tools-3.1.20260812/src/wg-quick/linux.bash"

echo "Upstream patches apply cleanly."
