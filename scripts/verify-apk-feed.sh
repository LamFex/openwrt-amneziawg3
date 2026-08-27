#!/bin/sh
# shellcheck disable=SC3043
set -eu

APK_TOOL="${1:-}"
FEED_DIR="${2:-}"
REPORT_DIR="${3:-}"
SIGNING_STATUS="${4:-}"
PUBLIC_KEY="${5:-}"

[ -x "$APK_TOOL" ] || {
	echo "APK host tool was not found: $APK_TOOL" >&2
	exit 2
}
if [ ! -d "$FEED_DIR" ] || [ ! -f "${FEED_DIR}/packages.adb" ]; then
	echo "APK feed directory is incomplete: $FEED_DIR" >&2
	exit 2
fi
if [ -z "$REPORT_DIR" ] || [ -e "$REPORT_DIR" ]; then
	echo "APK report directory must not already exist: $REPORT_DIR" >&2
	exit 2
fi
case "$SIGNING_STATUS" in
	unsigned-test) [ -z "$PUBLIC_KEY" ] ;;
	signed-release) [ -s "$PUBLIC_KEY" ] ;;
	*)
		echo "Unknown feed signing status: $SIGNING_STATUS" >&2
	exit 2
		;;
esac

VERIFY_TMP="$(mktemp -d "${TMPDIR:-/tmp}/awg3-apk-verify.XXXXXX")"
trap 'case "$VERIFY_TMP" in "${TMPDIR:-/tmp}"/awg3-apk-verify.*) rm -rf -- "$VERIFY_TMP" ;; esac' EXIT
mkdir -p "$REPORT_DIR"

"$APK_TOOL" --allow-untrusted adbdump --format json \
	"${FEED_DIR}/packages.adb" > "${REPORT_DIR}/feed-index.json"
jq -e '.packages | type == "array" and length == 6' \
	"${REPORT_DIR}/feed-index.json" >/dev/null

EXPECTED_NAMES='amneziawg3
amneziawg3-go
amneziawg3-tools
amneziawg3-tools-aliases
luci-i18n-amneziawg3-ru
luci-proto-amneziawg3'
INDEX_NAMES="$(jq -r '.packages[].name' "${REPORT_DIR}/feed-index.json" |
	LC_ALL=C sort)"
[ "$INDEX_NAMES" = "$EXPECTED_NAMES" ] || {
	echo "APK index package names are incomplete or duplicated." >&2
	printf '%s\n' "$INDEX_NAMES" >&2
	exit 1
}

set -- "${FEED_DIR}"/*.apk
if [ "$#" -ne 6 ] || [ ! -f "$1" ]; then
	echo "Expected exactly six APK package files." >&2
	exit 1
fi

for package do
	package_file="$(basename "$package")"
	"$APK_TOOL" --allow-untrusted verify "$package" >/dev/null
	"$APK_TOOL" --allow-untrusted adbdump --format json "$package" \
		> "${VERIFY_TMP}/${package_file}.json"
done

jq -s 'sort_by(.info.name)' "${VERIFY_TMP}"/*.apk.json \
	> "${REPORT_DIR}/package-metadata.json"

validate_metadata() {
	local name="$1"
	local version="$2"
	local arch="$3"
	local license="$4"

	jq -e --arg name "$name" --arg version "$version" --arg arch "$arch" \
		--arg license "$license" '
			map(select(.info.name == $name)) | length == 1 and
			.[0].info.version == $version and
			.[0].info.arch == $arch and
			.[0].info.license == $license and
			(.[0].info.maintainer | type == "string" and length > 0)
		' "${REPORT_DIR}/package-metadata.json" >/dev/null || {
		echo "Unexpected metadata for $name." >&2
		exit 1
	}
}

validate_metadata amneziawg3 3.1.20260814-r2 all MIT
validate_metadata amneziawg3-go 3.1.20260814-r2 aarch64_cortex-a53 MIT
validate_metadata amneziawg3-tools 3.1.20260812-r2 aarch64_cortex-a53 \
	'GPL-2.0-only AND Apache-2.0'
validate_metadata amneziawg3-tools-aliases 3.1.20260812-r2 all MIT
validate_metadata luci-i18n-amneziawg3-ru 3.1.20260814-r2 all Apache-2.0
validate_metadata luci-proto-amneziawg3 3.1.20260814-r2 all Apache-2.0

require_dependency() {
	local package="$1"
	local dependency="$2"

	jq -e --arg package "$package" --arg dependency "$dependency" '
		map(select(.info.name == $package))[0].info.depends // [] |
		map(.name) | index($dependency) != null
	' "${REPORT_DIR}/package-metadata.json" >/dev/null || {
		echo "$package does not depend on $dependency." >&2
		exit 1
	}
}

require_dependency amneziawg3 amneziawg3-go
require_dependency amneziawg3 amneziawg3-tools
require_dependency amneziawg3 luci-i18n-amneziawg3-ru
require_dependency amneziawg3 luci-proto-amneziawg3
require_dependency amneziawg3-tools amneziawg3-go
require_dependency amneziawg3-tools-aliases amneziawg3-tools
require_dependency luci-i18n-amneziawg3-ru luci-proto-amneziawg3
require_dependency luci-proto-amneziawg3 amneziawg3-tools

jq -r '.[] | .info.name as $package | .paths[]? |
	.name as $directory | .files[]? |
	[$package, (("/" + $directory + "/" + .name) | gsub("/+"; "/"))] |
	@tsv' "${REPORT_DIR}/package-metadata.json" |
	LC_ALL=C sort > "${REPORT_DIR}/installed-files.txt"

assert_package_files() {
	local package="$1"
	local expected="$2"
	local actual_file="${VERIFY_TMP}/${package}.files"
	local expected_file="${VERIFY_TMP}/${package}.expected"

	awk -F '\t' -v package="$package" '$1 == package { print $2 }' \
		"${REPORT_DIR}/installed-files.txt" | LC_ALL=C sort > "$actual_file"
	printf '%s\n' "$expected" | sed '/^$/d' | LC_ALL=C sort > "$expected_file"
	diff -u "$expected_file" "$actual_file" || {
		echo "Unexpected installed file list for $package." >&2
		exit 1
	}
}

assert_package_files amneziawg3 ''
assert_package_files amneziawg3-go '/usr/bin/amneziawg-go
/usr/libexec/amneziawg3/amneziawg3.init'
assert_package_files amneziawg3-tools '/lib/netifd/proto/amneziawg3.sh
/usr/bin/amneziawg3_watchdog
/usr/bin/awg-quick3
/usr/bin/awg3
/usr/libexec/amneziawg3/amneziawg3-key-helper
/usr/libexec/amneziawg3/awg
/usr/libexec/amneziawg3/awg-quick'
assert_package_files amneziawg3-tools-aliases '/usr/bin/awg
/usr/bin/awg-quick'
assert_package_files luci-i18n-amneziawg3-ru '/etc/uci-defaults/luci-i18n-amneziawg3-ru
/usr/lib/lua/luci/i18n/amneziawg3.ru.lmo'
assert_package_files luci-proto-amneziawg3 '/usr/share/rpcd/acl.d/luci-amneziawg3.json
/usr/share/rpcd/ucode/luci.amneziawg3
/www/luci-static/resources/protocol/amneziawg3.js'

if awk -F '\t' '$1 != "amneziawg3-tools-aliases" &&
	($2 == "/usr/bin/awg" || $2 == "/usr/bin/awg-quick") { found = 1 }
	END { exit !found }' "${REPORT_DIR}/installed-files.txt"; then
	echo "A non-alias package owns a standard AWG command path." >&2
	exit 1
fi

if [ "$SIGNING_STATUS" = signed-release ]; then
	KEYS_DIR="${VERIFY_TMP}/keys"
	mkdir -p "$KEYS_DIR"
	cp "$PUBLIC_KEY" "${KEYS_DIR}/awg-openwrt3.pem"
	"$APK_TOOL" --keys-dir "$KEYS_DIR" verify \
		"${FEED_DIR}/packages.adb" >/dev/null
else
	"$APK_TOOL" --allow-untrusted verify \
		"${FEED_DIR}/packages.adb" >/dev/null
fi

cat > "${VERIFY_TMP}/repositories.list" <<EOF
ndx file://${FEED_DIR}/packages.adb
ndx https://downloads.openwrt.org/releases/25.12.5/targets/mediatek/filogic/packages/packages.adb
ndx https://downloads.openwrt.org/releases/25.12.5/packages/aarch64_cortex-a53/base/packages.adb
ndx https://downloads.openwrt.org/releases/25.12.5/packages/aarch64_cortex-a53/luci/packages.adb
ndx https://downloads.openwrt.org/releases/25.12.5/packages/aarch64_cortex-a53/packages/packages.adb
ndx https://downloads.openwrt.org/releases/25.12.5/packages/aarch64_cortex-a53/routing/packages.adb
ndx https://downloads.openwrt.org/releases/25.12.5/packages/aarch64_cortex-a53/telephony/packages.adb
EOF
mkdir -p "${VERIFY_TMP}/root"
"$APK_TOOL" --root "${VERIFY_TMP}/root" \
	--arch aarch64_cortex-a53 \
	--repositories-file "${VERIFY_TMP}/repositories.list" \
	--allow-untrusted --cache=no --simulate \
	add --usermode amneziawg3 amneziawg3-tools-aliases \
		luci-i18n-amneziawg3-ru \
	> "${REPORT_DIR}/solver-plan.txt"

for package in amneziawg3 amneziawg3-go amneziawg3-tools \
	amneziawg3-tools-aliases luci-i18n-amneziawg3-ru \
	luci-proto-amneziawg3; do
	grep -Fq "$package" "${REPORT_DIR}/solver-plan.txt" || {
		echo "APK solver did not select $package." >&2
		exit 1
	}
done

cat > "${REPORT_DIR}/verification-summary.txt" <<EOF
Package-Count: 6
Feed-Signing: ${SIGNING_STATUS}
Index-Readable: yes
Package-Integrity: verified
Metadata-Allowlist: verified
Installed-File-Allowlist: verified
Dependency-Solver: verified
EOF

echo "APK metadata, files, index, and solver checks passed."
