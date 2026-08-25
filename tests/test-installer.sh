#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

REPOSITORY_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/awg3-installer.XXXXXX")"
trap 'case "$TEST_TMP" in "${TMPDIR:-/tmp}"/awg3-installer.*) rm -rf -- "$TEST_TMP" ;; esac' EXIT

cd "$REPOSITORY_ROOT"
command -v sha256sum >/dev/null 2>&1 || {
	echo 'sha256sum is required for installer fixture tests.' >&2
	exit 1
}

public_key_file="${TEST_TMP}/public-key"
printf '%s\n' 'fixture public key' > "$public_key_file"
public_key_hash="$(sha256sum "$public_key_file" | awk '{ print $1 }')"

write_release_metadata() {
	local root="$1"
	local board="$2"

	mkdir -p "$root/etc/apk/keys" "$root/etc/apk/repositories.d" \
		"$root/tmp/sysinfo" "$root/root" "$root/usr/bin"
	cat > "$root/etc/openwrt_release" <<'EOF'
DISTRIB_RELEASE='25.12.5'
DISTRIB_TARGET='mediatek/filogic'
DISTRIB_ARCH='aarch64_cortex-a53'
EOF
	printf '%s\n' "$board" > "$root/tmp/sysinfo/board_name"
	printf '%s\n' 'Cudy TR3000 v1' > "$root/tmp/sysinfo/model"
	printf '%s\n' 'old public key' > "$root/etc/apk/keys/awg-openwrt3.pem"
	printf '%s\n' 'https://existing.invalid/packages.adb' \
		> "$root/etc/apk/repositories.d/customfeeds.list"
	# shared-dependency is deliberately installed but not in world, modelling a
	# pre-existing auto/orphan dependency that rollback must still protect.
	printf '%s\n' busybox > "$root/etc/apk/world"
	chmod 0600 "$root/etc/apk/keys/awg-openwrt3.pem" \
		"$root/etc/apk/repositories.d/customfeeds.list" \
		"$root/etc/apk/world"
}

write_mocks() {
	local fixture="$1"
	local mockbin="${fixture}/mockbin"
	mkdir -p "$mockbin"

	cat > "$mockbin/uname" <<'MOCK'
#!/bin/sh
if [ "${1:-}" = '-r' ]; then
	printf '%s\n' '6.12.99-fixture'
else
	exec /usr/bin/uname "$@"
fi
MOCK

	cat > "$mockbin/wget" <<'MOCK'
#!/bin/sh
set -eu
output=
while [ "$#" -gt 0 ]; do
	case "$1" in
		-qO) output="$2"; shift 2 ;;
		*) shift ;;
	esac
done
[ -n "$output" ]
cp "$INSTALLER_PUBLIC_KEY" "$output"
MOCK

	cat > "$mockbin/apk" <<'MOCK'
#!/bin/sh
set -eu

printf '%s\n' "$*" >> "$APK_LOG"

db_put() {
	name="$1"
	version="$2"
	awk -F '\t' -v package="$name" '$1 != package' "$APK_DB" > "${APK_DB}.tmp"
	printf '%s\t%s\n' "$name" "$version" >> "${APK_DB}.tmp"
	mv "${APK_DB}.tmp" "$APK_DB"
}

db_remove() {
	name="$1"
	awk -F '\t' -v package="$name" '$1 != package' "$APK_DB" > "${APK_DB}.tmp"
	mv "${APK_DB}.tmp" "$APK_DB"
}

command_name="${1:-}"
[ "$#" -gt 0 ] && shift
case "$command_name" in
	query)
		pattern=
		summary=name
		match=name
		previous=
		for argument do
			if [ "$previous" = '--summarize' ]; then
				summary="$argument"
			fi
			if [ "$previous" = '--match' ]; then
				match="$argument"
			fi
			previous="$argument"
			pattern="$argument"
		done
		if [ "$match" = owner ]; then
			[ "$pattern" = /usr/bin/amneziawg-go ]
			printf '%s\n' "${APK_RUNTIME_OWNER:-amneziawg3-go}"
			exit 0
		fi
		if [ "$pattern" = '*' ]; then
			if [ "$summary" = package ]; then
				awk -F '\t' '{ print $1 "-" $2 }' "$APK_DB"
			else
				cut -f1 "$APK_DB"
			fi
		else
			if [ "$summary" = package ]; then
				awk -F '\t' -v package="$pattern" \
					'$1 == package { print $1 "-" $2 }' "$APK_DB"
			else
				awk -F '\t' -v package="$pattern" \
					'$1 == package { print $1 }' "$APK_DB"
			fi
		fi
		;;
	info)
		case "${1:-}" in
			-v)
				package="$2"
				awk -F '\t' -v package="$package" \
					'$1 == package { print $1 "-" $2; exit }' "$APK_DB"
				;;
			*) exit 2 ;;
		esac
		;;
	update)
		: ;;
	add)
		exact=1
		for package do
			case "$package" in
				*=*)
					name="${package%%=*}"
					version="${package#*=}"
					db_put "$name" "$version"
					;;
				*) exact=0 ;;
			esac
		done
		[ "$exact" -eq 0 ] || exit 0

		db_put amneziawg3 '3.1.20260814-r2'
		db_put amneziawg3-go '3.1.20260814-r2'
		db_put amneziawg3-tools '3.1.20260812-r2'
		db_put luci-proto-amneziawg3 '3.1.20260814-r2'
		db_put new-dependency '1-r1'
		if [ "${APK_FAIL_POSTINSTALL:-0}" -eq 1 ]; then
			# Simulate the solver changing a package that predated this run.
			db_put shared-dependency '2-r4'
		fi
		for package do
			[ "$package" != amneziawg3-tools-aliases ] || \
				db_put amneziawg3-tools-aliases '3.1.20260812-r2'
			grep -Fxq "$package" "$APK_WORLD" || \
				printf '%s\n' "$package" >> "$APK_WORLD"
		done
		mkdir -p "$(dirname "$APK_INIT_PATH")"
		ln -sf /usr/libexec/amneziawg3/amneziawg3.init "$APK_INIT_PATH"
		if [ "${APK_FAIL_POSTINSTALL:-0}" -eq 1 ]; then
			touch "$APK_BROKEN_MARKER"
			exit 17
		fi
		;;
	del)
		without_scripts=0
		packages=
		for argument do
			case "$argument" in
				--no-scripts) without_scripts=1 ;;
				--*) ;;
				*) packages="${packages} ${argument}" ;;
			esac
		done
		if [ -e "$APK_BROKEN_MARKER" ] && [ "$without_scripts" -eq 0 ]; then
			exit 23
		fi
		for package in $packages; do
			db_remove "$package"
		done
		rm -f "$APK_BROKEN_MARKER"
		;;
	*) exit 2 ;;
esac
MOCK

	chmod 0755 "$mockbin/uname" "$mockbin/wget" "$mockbin/apk"
}

render_installer() {
	local fixture="$1"
	local root="${fixture}/root"
	local rendered="${fixture}/install.sh"
	local mockbin="${fixture}/mockbin"
	local temp_parent="${fixture}/tmp"
	mkdir -p "$temp_parent"

	sed \
		-e 's|@FEED_BASE_URL@|https://example.invalid/feed|g' \
		-e "s|@PUBLIC_KEY_SHA256@|${public_key_hash}|g" \
		-e "s|^INSTALL_ROOT=$|INSTALL_ROOT='${root}'|" \
		-e "s|^TMP_PARENT=/tmp$|TMP_PARENT='${temp_parent}'|" \
		-e "s|^PATH=/usr/sbin:/usr/bin:/sbin:/bin$|PATH='${mockbin}:/usr/sbin:/usr/bin:/sbin:/bin'|" \
		scripts/install.sh.in > "$rendered"
	chmod 0755 "$rendered"
}

new_fixture() {
	local name="$1"
	local board="$2"
	local fixture="${TEST_TMP}/${name}"
	mkdir -p "$fixture"
	write_release_metadata "${fixture}/root" "$board"
	printf '%s\t%s\n' busybox '1-r1' shared-dependency '2-r3' \
		> "${fixture}/installed.tsv"
	: > "${fixture}/apk.log"
	write_mocks "$fixture"
	render_installer "$fixture"
	printf '%s' "$fixture"
}

run_installer() {
	local fixture="$1"
	local fail_postinstall="$2"
	local output="$3"

	AWG3_INSTALL_CONFIRM=YES \
	APK_DB="${fixture}/installed.tsv" \
	APK_LOG="${fixture}/apk.log" \
	APK_WORLD="${fixture}/root/etc/apk/world" \
	APK_INIT_PATH="${fixture}/root/etc/init.d/amneziawg3" \
	APK_BROKEN_MARKER="${fixture}/broken-script" \
	APK_FAIL_POSTINSTALL="$fail_postinstall" \
	APK_RUNTIME_OWNER="${APK_RUNTIME_OWNER:-amneziawg3-go}" \
	INSTALLER_PUBLIC_KEY="$public_key_file" \
		"${fixture}/install.sh" > "$output" 2>&1
}

file_mode() {
	if stat -c '%a' "$1" >/dev/null 2>&1; then
		stat -c '%a' "$1"
	else
		stat -f '%Lp' "$1"
	fi
}

# A broken post-install script must trigger a retry with --no-scripts and
# restore the exact package and local file snapshots.
fixture="$(new_fixture rollback cudy,tr3000-v1)"
cp "${fixture}/installed.tsv" "${fixture}/installed.before"
cp "${fixture}/root/etc/apk/world" "${fixture}/world.before"
cp "${fixture}/root/etc/apk/keys/awg-openwrt3.pem" "${fixture}/key.before"
cp "${fixture}/root/etc/apk/repositories.d/customfeeds.list" \
	"${fixture}/feed.before"
if run_installer "$fixture" 1 "${fixture}/output"; then
	echo 'Broken post-install fixture unexpectedly succeeded.' >&2
	exit 1
fi
cmp "${fixture}/installed.before" "${fixture}/installed.tsv"
cmp "${fixture}/world.before" "${fixture}/root/etc/apk/world"
cmp "${fixture}/key.before" "${fixture}/root/etc/apk/keys/awg-openwrt3.pem"
cmp "${fixture}/feed.before" \
	"${fixture}/root/etc/apk/repositories.d/customfeeds.list"
[[ "$(file_mode "${fixture}/root/etc/apk/world")" == 600 ]]
[[ "$(file_mode "${fixture}/root/etc/apk/keys/awg-openwrt3.pem")" == 600 ]]
[[ ! -e "${fixture}/root/etc/init.d/amneziawg3" && \
	! -L "${fixture}/root/etc/init.d/amneziawg3" ]]
grep -Fq 'Rollback complete: packages, versions, world, feed, key, and init facade match' \
	"${fixture}/output"
grep -Fq 'retrying remaining broken-script packages without package scripts' \
	"${fixture}/output"
grep -Eq '^del .*--no-scripts' "${fixture}/apk.log"
grep -Fq 'add shared-dependency=2-r3' "${fixture}/apk.log"
if grep -Eq '^del .*shared-dependency' "${fixture}/apk.log"; then
	echo 'Rollback attempted to remove a pre-existing shared dependency.' >&2
	exit 1
fi
[[ -z "$(find "${fixture}/tmp" -name 'awg-openwrt3.pem.*' -print -quit)" ]]

# An exact board_name mismatch stops before any package-manager operation.
fixture="$(new_fixture wrong-board cudy,tr3000-v1-ubootmod)"
if run_installer "$fixture" 0 "${fixture}/output"; then
	echo 'Unknown board fixture unexpectedly succeeded.' >&2
	exit 1
fi
[[ ! -s "${fixture}/apk.log" ]]
grep -Fq "expected exactly cudy,tr3000-v1" "${fixture}/output"

# An unowned or dangling legacy runtime path is a collision, not an available
# namespace. The installer must stop before an APK mutation.
fixture="$(new_fixture runtime-collision cudy,tr3000-v1)"
ln -s /missing/legacy-runtime "$fixture/root/usr/bin/amneziawg-go"
if APK_RUNTIME_OWNER=legacy-runtime \
	run_installer "$fixture" 0 "${fixture}/output"; then
	echo 'Dangling legacy runtime collision unexpectedly succeeded.' >&2
	exit 1
fi
if grep -Eq '^(update|add|del)( |$)' "${fixture}/apk.log"; then
	echo 'Runtime collision reached a package mutation.' >&2
	exit 1
fi
grep -Fq 'existing /usr/bin/amneziawg-go is not owned by amneziawg3-go' \
	"${fixture}/output"

# Existing AWG2 tools and command collisions must be preserved; only the
# optional aliases are skipped.
fixture="$(new_fixture alias-collision cudy,tr3000-v1)"
printf '%s\t%s\n' amneziawg-tools '2.0-r7' >> "${fixture}/installed.tsv"
printf '%s\n' amneziawg-tools >> "${fixture}/root/etc/apk/world"
printf '%s\n' '# existing AWG command' > "${fixture}/root/usr/bin/awg"
if ! run_installer "$fixture" 0 "${fixture}/output"; then
	cat "${fixture}/output" >&2
	exit 1
fi
grep -Fq $'amneziawg-tools\t2.0-r7' "${fixture}/installed.tsv"
if grep -Fq $'amneziawg3-tools-aliases\t' "${fixture}/installed.tsv"; then
	echo 'Optional aliases were installed over an existing AWG command.' >&2
	exit 1
fi
grep -Fq 'Existing AWG tools detected; standard awg aliases will not be installed.' \
	"${fixture}/output"

# A dangling command symlink is still an occupied namespace and must not be
# overwritten by the optional aliases package.
fixture="$(new_fixture dangling-alias cudy,tr3000-v1)"
ln -s /missing/legacy-awg "$fixture/root/usr/bin/awg-quick"
if ! run_installer "$fixture" 0 "${fixture}/output"; then
	cat "${fixture}/output" >&2
	exit 1
fi
if grep -Fq $'amneziawg3-tools-aliases\t' "${fixture}/installed.tsv"; then
	echo 'Optional aliases were installed over a dangling command symlink.' >&2
	exit 1
fi
[[ "$(readlink "$fixture/root/usr/bin/awg-quick")" == /missing/legacy-awg ]]

# The one-command installer is intentionally first-install only and must stop
# before update/add/del when any project package already exists.
fixture="$(new_fixture existing-project cudy,tr3000-v1)"
printf '%s\t%s\n' amneziawg3-tools '3.1.20260812-r1' >> \
	"${fixture}/installed.tsv"
cp "${fixture}/installed.tsv" "${fixture}/installed.before"
if run_installer "$fixture" 0 "${fixture}/output"; then
	echo 'Existing-project fixture unexpectedly succeeded.' >&2
	exit 1
fi
cmp "${fixture}/installed.before" "${fixture}/installed.tsv"
if grep -Eq '^(update|add|del)( |$)' "${fixture}/apk.log"; then
	echo 'First-install gate mutated packages for an existing project install.' >&2
	exit 1
fi
grep -Fq 'this installer is first-install only' "${fixture}/output"

grep -Fq 'umask 077' scripts/install.sh.in
grep -Fq 'mktemp "${TMP_PARENT}/awg-openwrt3.pem.XXXXXX"' scripts/install.sh.in
grep -Fq -- '--summarize package "$package"' scripts/install.sh.in
if grep -Eq 'apk[[:space:]]+info[[:space:]]+-v' scripts/install.sh.in; then
	echo 'Installer uses human-readable apk info output for version snapshots.' >&2
	exit 1
fi
if rg -n 'awg-openwrt3\.pem\.\$\$|AWG3_ALLOW_UNTESTED_DEVICE' \
		scripts/install.sh.in >/dev/null; then
	echo 'Installer contains a predictable key path or allowlist bypass.' >&2
	exit 1
fi
if rg -n '^[[:space:]]*(/etc/init.d/network|ifup|reboot)([[:space:]]|$)' \
		scripts/install.sh.in >/dev/null; then
	echo 'Installer must not mutate network lifecycle automatically.' >&2
	exit 1
fi

echo 'Installer rollback and allowlist tests passed.'
