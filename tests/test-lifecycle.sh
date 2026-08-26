#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

REPOSITORY_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/awg3-lifecycle.XXXXXX")"
trap 'case "$TEST_TMP" in "${TMPDIR:-/tmp}"/awg3-lifecycle.*) rm -rf -- "$TEST_TMP" ;; esac' EXIT

cd "$REPOSITORY_ROOT"

extract_hook() {
	local hook="$1"
	local output="$2"
	local makefile="${3:-amneziawg-go/Makefile}"
	awk -v marker="define ${hook}" '
		$0 == marker { active = 1; next }
		active && $0 == "endef" { exit }
		active { print }
	' "$makefile" | sed 's/\$\$/\$/g' > "$output"
	chmod 0755 "$output"
}

extract_hook Package/amneziawg3-go/preinst "${TEST_TMP}/preinst"
extract_hook Package/amneziawg3-go/postinst "${TEST_TMP}/postinst"
extract_hook Package/amneziawg3-go/prerm "${TEST_TMP}/prerm"
extract_hook Package/amneziawg3-tools/prerm "${TEST_TMP}/tools-prerm" \
	amneziawg-tools/Makefile

for hook in preinst postinst prerm tools-prerm; do
	[[ -s "${TEST_TMP}/${hook}" ]]
	sh -n "${TEST_TMP}/${hook}"
done

expected_target=/usr/libexec/amneziawg3/amneziawg3.init

inode_of() {
	if stat -c '%i' "$1" >/dev/null 2>&1; then
		stat -c '%i' "$1"
	else
		stat -f '%i' "$1"
	fi
}

# First install and upgrade both preserve the exact package-owned facade and
# do not invoke an init/network action.
root="${TEST_TMP}/normal/root"
mkdir -p "$root"
IPKG_INSTROOT="$root" "${TEST_TMP}/preinst"
IPKG_INSTROOT="$root" "${TEST_TMP}/postinst"
[[ -L "$root/etc/init.d/amneziawg3" ]]
[[ "$(readlink "$root/etc/init.d/amneziawg3")" == "$expected_target" ]]
first_inode="$(inode_of "$root/etc/init.d/amneziawg3")"
IPKG_INSTROOT="$root" "${TEST_TMP}/preinst"
IPKG_INSTROOT="$root" "${TEST_TMP}/postinst"
[[ "$(readlink "$root/etc/init.d/amneziawg3")" == "$expected_target" ]]
[[ "$(inode_of "$root/etc/init.d/amneziawg3")" == "$first_inode" ]]

# A foreign file or symlink is never replaced by preinst or postinst.
root="${TEST_TMP}/foreign-file/root"
mkdir -p "$root/etc/init.d"
printf '%s\n' foreign > "$root/etc/init.d/amneziawg3"
if IPKG_INSTROOT="$root" "${TEST_TMP}/preinst" >/dev/null 2>&1; then
	echo 'preinst accepted a foreign init file.' >&2
	exit 1
fi
if IPKG_INSTROOT="$root" "${TEST_TMP}/postinst" >/dev/null 2>&1; then
	echo 'postinst replaced a foreign init file.' >&2
	exit 1
fi
grep -Fxq foreign "$root/etc/init.d/amneziawg3"

root="${TEST_TMP}/foreign-link/root"
mkdir -p "$root/etc/init.d"
ln -s /foreign/owner "$root/etc/init.d/amneziawg3"
if IPKG_INSTROOT="$root" "${TEST_TMP}/preinst" >/dev/null 2>&1; then
	echo 'preinst accepted a foreign init symlink.' >&2
	exit 1
fi
[[ "$(readlink "$root/etc/init.d/amneziawg3")" == /foreign/owner ]]

# Uninstall removes only the exact package-owned symlink. Repeated uninstall
# is a no-op; a foreign symlink survives.
root="${TEST_TMP}/remove/root"
mkdir -p "$root/etc/init.d"
ln -s "$expected_target" "$root/etc/init.d/amneziawg3"
IPKG_INSTROOT="$root" "${TEST_TMP}/prerm"
[[ ! -e "$root/etc/init.d/amneziawg3" && ! -L "$root/etc/init.d/amneziawg3" ]]
IPKG_INSTROOT="$root" "${TEST_TMP}/prerm"
ln -s /foreign/owner "$root/etc/init.d/amneziawg3"
IPKG_INSTROOT="$root" "${TEST_TMP}/prerm"
[[ "$(readlink "$root/etc/init.d/amneziawg3")" == /foreign/owner ]]

if rg -n '(/etc/init\.d/network|\bifup\b|\bifdown\b|\breboot\b)' \
		"${TEST_TMP}/preinst" "${TEST_TMP}/postinst" >/dev/null; then
	echo 'Install or upgrade hooks contain a network lifecycle action.' >&2
	exit 1
fi

# Simulate live-root tools pre-deinstall with a private rewritten copy. The
# hook must stop through the exact symlink before its handler package vanishes.
tools_target="${TEST_TMP}/tools-prerm-target"
tools_init="${TEST_TMP}/tools-prerm-init"
cat > "$tools_target" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >> "$TOOLS_PRERM_CALLS"
EOF
chmod 0755 "$tools_target"
ln -s "$tools_target" "$tools_init"
sed \
	-e "s|init_path=\"\${IPKG_INSTROOT}/etc/init.d/amneziawg3\"|init_path='${tools_init}'|" \
	-e "s|init_target=\"/usr/libexec/amneziawg3/amneziawg3.init\"|init_target='${tools_target}'|" \
	"${TEST_TMP}/tools-prerm" > "${TEST_TMP}/tools-prerm-live"
chmod 0755 "${TEST_TMP}/tools-prerm-live"
TOOLS_PRERM_CALLS="${TEST_TMP}/tools-prerm-calls" \
	IPKG_INSTROOT='' "${TEST_TMP}/tools-prerm-live"
grep -Fxq stop "${TEST_TMP}/tools-prerm-calls"

if ! grep -Fq 'APK may continue removal, verify residual processes and links' \
		amneziawg-tools/Makefile; then
	echo 'Tools package lacks a visible pre-deinstall teardown warning.' >&2
	exit 1
fi

# Exercise the init facade itself: auto=0 is skipped by start/restart, but stop
# still tears down an already-running interface.
sed '/^\. \/lib\/functions\.sh$/d' amneziawg-go/files/amneziawg3.init \
	> "${TEST_TMP}/init-under-test"

append() {
	local destination="$1"
	local value="$2"
	local current="${!destination:-}"
	printf -v "$destination" '%s' "${current:+${current} }${value}"
}
config_load() { :; }
config_foreach() {
	local callback="$1"
	local type="$2"
	[[ "$type" == interface ]] && "$callback" awg3
}
config_get() {
	local destination="$1"
	local section="$2"
	local option="$3"
	local value="${4:-}"
	case "$section:$option" in
		awg3:proto) value=amneziawg3 ;;
		awg3:auto) value="$TEST_AUTO" ;;
	esac
	printf -v "$destination" '%s' "$value"
}
config_get_bool() { config_get "$@"; }
ifup() { printf 'ifup %s\n' "$1" >> "${TEST_TMP}/init-calls"; }
ifdown() { printf 'ifdown %s\n' "$1" >> "${TEST_TMP}/init-calls"; }
ubus() { return 1; }
jsonfilter() { return 1; }

# shellcheck source=/dev/null
source "${TEST_TMP}/init-under-test"
interface_is_up() { return 1; }
: > "${TEST_TMP}/init-calls"
TEST_AUTO=0
start
[[ ! -s "${TEST_TMP}/init-calls" ]]
restart
grep -Fxq 'ifdown awg3' "${TEST_TMP}/init-calls"
if grep -Fq 'ifup awg3' "${TEST_TMP}/init-calls"; then
	echo 'Init facade started an auto=0 interface.' >&2
	exit 1
fi
: > "${TEST_TMP}/init-calls"
TEST_AUTO=1
start
grep -Fxq 'ifup awg3' "${TEST_TMP}/init-calls"

# The documented uninstall plan keeps aliases first, performs one conditional
# transaction, and is repeat-safe when no project package remains.
alias_line="$(rg -n '^  amneziawg3-tools-aliases \\$' README.md | cut -d: -f1)"
meta_line="$(rg -n '^  amneziawg3 \\$' README.md | cut -d: -f1)"
[[ -n "$alias_line" && -n "$meta_line" && "$alias_line" -lt "$meta_line" ]]
grep -Fq '[ -z "$packages" ] || apk del $packages' README.md
grep -Fq '/etc/init.d/amneziawg3 stop' README.md

uninstall_plan() {
	local installed=" $1 "
	local package packages=
	for package in \
		amneziawg3-tools-aliases \
		amneziawg3 \
		luci-i18n-amneziawg3-ru \
		luci-proto-amneziawg3 \
		amneziawg3-tools \
		amneziawg3-go; do
		case "$installed" in
			*" $package "*) packages="${packages} ${package}" ;;
		esac
	done
	printf '%s' "$packages"
}

[[ "$(uninstall_plan 'amneziawg3-tools-aliases amneziawg3 amneziawg3-tools')" == \
	' amneziawg3-tools-aliases amneziawg3 amneziawg3-tools' ]]
[[ "$(uninstall_plan 'amneziawg3 amneziawg3-tools')" == \
	' amneziawg3 amneziawg3-tools' ]]
[[ "$(uninstall_plan 'amneziawg3 luci-i18n-amneziawg3-ru luci-proto-amneziawg3')" == \
	' amneziawg3 luci-i18n-amneziawg3-ru luci-proto-amneziawg3' ]]
[[ -z "$(uninstall_plan '')" ]]

echo 'Package and init lifecycle tests passed.'
