#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

REPOSITORY_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/awg3-tests.XXXXXX")"
trap 'case "$TEST_TMP" in "${TMPDIR:-/tmp}"/awg3-tests.*) rm -rf -- "$TEST_TMP" ;; esac' EXIT

cd "$REPOSITORY_ROOT"

AWG3=/usr/bin/true
AWG3_GO="$AWG3"
AWG3_SOCKET_DIR="${TEST_TMP}/run"
INCLUDE_ONLY=1

config_value() {
	case "$1:$2" in
		awg3:private_key) printf '%s' 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' ;;
		awg3:listen_port) printf '%s' '4242' ;;
		awg3:fwmark) printf '%s' '0xca6c' ;;
		awg3:addresses) printf '%s' '10.10.0.2/32' ;;
		awg3:jc) printf '%s' '4' ;;
		awg3:jmin) printf '%s' '40' ;;
		awg3:jmax) printf '%s' '70' ;;
		awg3:s1|awg3:s2|awg3:s3|awg3:s4) printf '%s' '12' ;;
		awg3:h1) printf '%s' '1000000-2000000' ;;
		awg3:h2) printf '%s' '2000001' ;;
		awg3:i1) printf '%s' 'GET / HTTP/1.1' ;;
		awg3:header_protection_key) printf '%s' 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=' ;;
		awg3:content_padding_addition) printf '%s' '10-30' ;;
		awg3:rekey_after_time) printf '%s' '120-180' ;;
		awg3:random_trailers) printf '%s' '1' ;;
		peer1:public_key) printf '%s' 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=' ;;
		peer1:allowed_ips) printf '%s' '0.0.0.0/0 ::/0' ;;
		peer1:endpoint_host) printf '%s' '203.0.113.10' ;;
		peer1:endpoint_port) printf '%s' '4242' ;;
		peer1:persistent_keepalive) printf '%s' '20-30' ;;
		peer1:route_allowed_ips) printf '%s' "${TEST_ROUTE_ALLOWED:-0}" ;;
		peer2:disabled) printf '%s' '1' ;;
		*) return 1 ;;
	esac
}

config_get() {
	local destination="$1"
	local section="$2"
	local option="$3"
	local default_value="${4:-}"
	local value="$default_value"

	if config_value "$section" "$option" > "${TEST_TMP}/value"; then
		value="$(< "${TEST_TMP}/value")"
	fi
	printf -v "$destination" '%s' "$value"
}

config_get_bool() {
	config_get "$@"
}

config_foreach() {
	local callback="$1"
	local type="$2"

	if [[ "$type" == "amneziawg3_awg3" ]]; then
		"$callback" peer1
		"$callback" peer2
	fi
}

source amneziawg-tools/files/amneziawg3.sh

config_load() {
	:
}

awg3_load_interface_config awg3
awg3_emit_config awg3 > "${TEST_TMP}/actual.conf"
diff -u tests/fixtures/expected-awg3.conf "${TEST_TMP}/actual.conf"

awg3_valid_interface_name awg3
awg3_valid_interface_name awg3-client
if awg3_valid_interface_name 'this-name-is-too-long'; then
	echo "Interface length validation did not fail." >&2
	exit 1
fi
if awg3_valid_interface_name 'bad name'; then
	echo "Interface character validation did not fail." >&2
	exit 1
fi

if awg3_value_is_single_line $'line one\nline two'; then
	echo "Multiline value validation did not fail." >&2
	exit 1
fi
if awg3_value_is_single_line $'line one\rline two'; then
	echo "Carriage-return validation did not fail." >&2
	exit 1
fi

if grep -q AdvancedSecurity "${TEST_TMP}/actual.conf"; then
	echo "AdvancedSecurity was emitted for the userspace UAPI." >&2
	exit 1
fi

proto_add_ipv4_route() {
	printf 'ipv4 %s %s\n' "$1" "$2" >> "${TEST_TMP}/routes"
}

proto_add_ipv6_route() {
	printf 'ipv6 %s %s\n' "$1" "$2" >> "${TEST_TMP}/routes"
}

: > "${TEST_TMP}/routes"
awg3_add_peer_routes peer1
if [[ -s "${TEST_TMP}/routes" ]]; then
	echo "Peer routes were emitted without explicit route_allowed_ips." >&2
	exit 1
fi
TEST_ROUTE_ALLOWED=1
awg3_add_peer_routes peer1
grep -Fxq 'ipv4 0.0.0.0 0' "${TEST_TMP}/routes"
grep -Fxq 'ipv6 :: 0' "${TEST_TMP}/routes"

if grep -q 'amneziawg3-tools-aliases' amneziawg3/Makefile; then
	echo "Default meta-package unexpectedly depends on standard command aliases." >&2
	exit 1
fi
grep -q 'CONFLICTS:=amneziawg-tools' amneziawg-tools-aliases/Makefile
grep -q 'CONFLICTS:=amneziawg-go' amneziawg-go/Makefile
grep -Fq 'Package/amneziawg3-go/DEPENDS := $(Package/amneziawg3-go/DEPENDS)$(comma) !amneziawg-go' \
	amneziawg-go/Makefile
grep -Fq 'Package/amneziawg3-tools/DEPENDS := $(Package/amneziawg3-tools/DEPENDS)$(comma) !amneziawg-tools' \
	amneziawg-tools/Makefile
grep -Fq 'Package/amneziawg3-tools-aliases/DEPENDS := $(Package/amneziawg3-tools-aliases/DEPENDS)$(comma) !amneziawg-tools' \
	amneziawg-tools-aliases/Makefile
grep -q 'CONFLICTS:=amneziawg-tools' amneziawg-tools/Makefile
grep -q 'DEPENDS:=+amneziawg3-go' amneziawg-tools/Makefile
grep -Fq 'proto_run_command "$config" "$AWG3_GO" -f "$config"' \
	amneziawg-tools/files/amneziawg3.sh
grep -Fq 'proto_kill_command "$config" 15' \
	amneziawg-tools/files/amneziawg3.sh
if grep -Eq '(killall|pidof|rm[[:space:]]+-f.*\.sock)' \
	amneziawg-tools/files/amneziawg3.sh; then
	echo "The netifd helper must not claim processes or sockets by discovery." >&2
	exit 1
fi
grep -Fq '"$AWG3" syncconf "$config" /dev/stdin' \
	amneziawg-tools/files/amneziawg3.sh

# The OpenWrt Makefile expression is intentionally matched as a literal string.
# shellcheck disable=SC2016
if grep -Fq '$(1)/etc/init.d/amneziawg3' amneziawg-go/Makefile; then
	echo "Init facade must not be tracked under /etc/init.d by the APK." >&2
	exit 1
fi
grep -q 'init_target="/usr/libexec/amneziawg3/amneziawg3.init"' \
	amneziawg-go/Makefile
grep -q '^APK_PRIVATE_KEY=private-key.pem$' scripts/build-sdk.sh
grep -q '^APK_PUBLIC_KEY=public-key.pem$' scripts/build-sdk.sh
if grep -Eq '(^|[[:space:]])key-build(\.pub)?([[:space:]]|$)' scripts/build-sdk.sh; then
	echo "OpenWrt 25.12 APK signing must not use legacy key-build names." >&2
	exit 1
fi
# The patched shell expression is intentionally matched as a literal string.
# shellcheck disable=SC2016
grep -Fq '/etc/amnezia/amneziawg3/$CONFIG_FILE.conf' \
	amneziawg-tools/patches/020-openwrt-userspace-only.patch
grep -Fq '/etc/amnezia/amneziawg3/' amneziawg-tools/Makefile
grep -A1 '^define Package/amneziawg3/install$' amneziawg3/Makefile |
	grep -q 'true'
grep -Fq 'AWGTOOLS_COMMIT=\"v${TOOLS_VERSION}\"' scripts/verify-upstream.sh
grep -Fq 'DISTRIB_TARGET:-}' scripts/install.sh.in
grep -Fq '6.12.*)' scripts/install.sh.in
if grep -Fq 'AWG3_ALLOW_UNTESTED_DEVICE' scripts/install.sh.in; then
	echo "The first-release installer must not bypass the device allowlist." >&2
	exit 1
fi

go_package_version="$(sed -n 's/^PKG_VERSION:=//p' amneziawg-go/Makefile)"
go_build_version="$(sed -n 's/^AWG_GO_VERSION=//p' scripts/build-sdk.sh)"
go_verify_version="$(sed -n 's/^GO_VERSION=//p' scripts/verify-upstream.sh)"
tools_package_version="$(sed -n 's/^PKG_VERSION:=//p' amneziawg-tools/Makefile)"
tools_build_version="$(sed -n 's/^AWG_TOOLS_VERSION=//p' scripts/build-sdk.sh)"
tools_verify_version="$(sed -n 's/^TOOLS_VERSION=//p' scripts/verify-upstream.sh)"
go_package_hash="$(sed -n 's/^PKG_HASH:=//p' amneziawg-go/Makefile)"
go_build_hash="$(sed -n 's/^AWG_GO_SHA256=//p' scripts/build-sdk.sh)"
go_verify_hash="$(sed -n 's/^GO_HASH=//p' scripts/verify-upstream.sh)"
tools_package_hash="$(sed -n 's/^PKG_HASH:=//p' amneziawg-tools/Makefile)"
tools_build_hash="$(sed -n 's/^AWG_TOOLS_SHA256=//p' scripts/build-sdk.sh)"
tools_verify_hash="$(sed -n 's/^TOOLS_HASH=//p' scripts/verify-upstream.sh)"
[[ "$go_package_version" == "$go_build_version" ]]
[[ "$go_package_version" == "$go_verify_version" ]]
[[ "$tools_package_version" == "$tools_build_version" ]]
[[ "$tools_package_version" == "$tools_verify_version" ]]
[[ "$go_package_hash" == "$go_build_hash" ]]
[[ "$go_package_hash" == "$go_verify_hash" ]]
[[ "$tools_package_hash" == "$tools_build_hash" ]]
[[ "$tools_package_hash" == "$tools_verify_hash" ]]

bash tests/test-j-validation.sh
bash tests/test-key-helper.sh
bash tests/test-installer.sh
bash tests/test-lifecycle.sh
bash tests/test-repository-policy.sh
bash tests/test-ucode-runtime.sh

if command -v node >/dev/null 2>&1; then
	node tests/test-luci-js.js
else
	echo "Node.js not found; LuCI JavaScript behavioral tests were skipped." >&2
fi

echo "All fixture tests passed."
