#!/bin/sh
# shellcheck disable=SC3043
set -eu

APK_TOOL="${1:-}"
FEED_DIR="${2:-}"
REPORT_DIR="${3:-}"
METADATA_JSON="${4:-}"
BASE_REPOSITORIES_FILE="${5:-}"
APK_ARCH=aarch64_cortex-a53

[ -x "$APK_TOOL" ] || {
	echo "APK host tool was not found: $APK_TOOL" >&2
	exit 2
}
if [ ! -d "$FEED_DIR" ] || [ ! -f "${FEED_DIR}/packages.adb" ]; then
	echo "APK feed directory is incomplete: $FEED_DIR" >&2
	exit 2
fi
[ -d "$REPORT_DIR" ] || {
	echo "APK report directory does not exist: $REPORT_DIR" >&2
	exit 2
}
[ -s "$METADATA_JSON" ] || {
	echo "APK package metadata is unavailable: $METADATA_JSON" >&2
	exit 2
}
[ -s "$BASE_REPOSITORIES_FILE" ] || {
	echo "APK repository list is unavailable: $BASE_REPOSITORIES_FILE" >&2
	exit 2
}

LIFECYCLE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/awg3-apk-lifecycle.XXXXXX")"
trap 'case "$LIFECYCLE_TMP" in "${TMPDIR:-/tmp}"/awg3-apk-lifecycle.*) rm -rf -- "$LIFECYCLE_TMP" ;; esac' EXIT

REPORT_FILE="${REPORT_DIR}/apk-lifecycle-report.txt"
: > "$REPORT_FILE"

metadata_version() {
	local package="$1"

	jq -er --arg package "$package" '
		map(select(.info.name == $package)) as $matches |
		if ($matches | length) == 1 then
			$matches[0].info.version
		else
			error("missing or duplicate package metadata")
		end
	' "$METADATA_JSON"
}

GO_R3_VERSION="$(metadata_version amneziawg3-go)"
TOOLS_R3_VERSION="$(metadata_version amneziawg3-tools)"
ALIASES_R3_VERSION="$(metadata_version amneziawg3-tools-aliases)"
[ "$GO_R3_VERSION" = 3.1.20260814-r3 ]
[ "$TOOLS_R3_VERSION" = 3.1.20260812-r3 ]
[ "$ALIASES_R3_VERSION" = 3.1.20260812-r3 ]

make_payload_file() {
	local root="$1"
	local pathname="$2"
	local contents="$3"
	local mode="$4"

	mkdir -p "$(dirname "${root}/${pathname}")"
	printf '%s\n' "$contents" > "${root}/${pathname}"
	chmod "$mode" "${root}/${pathname}"
}

make_payload_symlink() {
	local root="$1"
	local pathname="$2"
	local target="$3"

	mkdir -p "$(dirname "${root}/${pathname}")"
	ln -s "$target" "${root}/${pathname}"
}

build_fixture_package() {
	local repository="$1"
	local payload="$2"
	local name="$3"
	local version="$4"
	local arch="$5"
	local depends="$6"
	local output="${repository}/${name}-${version}.apk"

	if [ -n "$depends" ]; then
		"$APK_TOOL" mkpkg \
			--info "name:${name}" \
			--info "version:${version}" \
			--info "arch:${arch}" \
			--info 'license:MIT' \
			--info "origin:awg3-ci-fixture/${name}" \
			--info 'maintainer:AWG OpenWrt3 CI fixture' \
			--info 'url:https://example.invalid/awg3-ci-fixture' \
			--info "description:Disposable ${name} lifecycle fixture" \
			--info "depends:${depends}" \
			--files "$payload" \
			--output "$output"
	else
		"$APK_TOOL" mkpkg \
			--info "name:${name}" \
			--info "version:${version}" \
			--info "arch:${arch}" \
			--info 'license:MIT' \
			--info "origin:awg3-ci-fixture/${name}" \
			--info 'maintainer:AWG OpenWrt3 CI fixture' \
			--info 'url:https://example.invalid/awg3-ci-fixture' \
			--info "description:Disposable ${name} lifecycle fixture" \
			--files "$payload" \
			--output "$output"
	fi
}

index_fixture_repository() {
	local repository="$1"

	(
		cd "$repository"
		"$APK_TOOL" --allow-untrusted mkndx \
			--output packages.adb ./*.apk
	)
}

LEGACY_REPOSITORY="${LIFECYCLE_TMP}/legacy-repository"
R2_REPOSITORY="${LIFECYCLE_TMP}/r2-repository"
mkdir -p "$LEGACY_REPOSITORY" "$R2_REPOSITORY"

payload="${LIFECYCLE_TMP}/payload-legacy-go"
mkdir -p "$payload"
make_payload_file "$payload" usr/bin/amneziawg-go \
	'AWG2 runtime fixture: do not replace' 0755
build_fixture_package "$LEGACY_REPOSITORY" "$payload" \
	amneziawg-go 2.0-r7 "$APK_ARCH" ''

payload="${LIFECYCLE_TMP}/payload-legacy-tools"
mkdir -p "$payload"
make_payload_file "$payload" usr/bin/awg \
	'AWG2 awg fixture: do not replace' 0755
make_payload_file "$payload" usr/bin/awg-quick \
	'AWG2 awg-quick fixture: do not replace' 0755
build_fixture_package "$LEGACY_REPOSITORY" "$payload" \
	amneziawg-tools 2.0-r7 "$APK_ARCH" ''
index_fixture_repository "$LEGACY_REPOSITORY"

payload="${LIFECYCLE_TMP}/payload-r2-go"
mkdir -p "$payload"
make_payload_file "$payload" usr/bin/amneziawg-go \
	'AWG3 r2 runtime fixture' 0755
build_fixture_package "$R2_REPOSITORY" "$payload" \
	amneziawg3-go 3.1.20260814-r2 "$APK_ARCH" ''

payload="${LIFECYCLE_TMP}/payload-r2-tools"
mkdir -p "$payload"
make_payload_file "$payload" usr/bin/awg3 \
	'AWG3 r2 awg fixture' 0755
make_payload_file "$payload" usr/bin/awg-quick3 \
	'AWG3 r2 awg-quick fixture' 0755
build_fixture_package "$R2_REPOSITORY" "$payload" \
	amneziawg3-tools 3.1.20260812-r2 "$APK_ARCH" amneziawg3-go

payload="${LIFECYCLE_TMP}/payload-r2-aliases"
mkdir -p "$payload"
make_payload_symlink "$payload" usr/bin/awg awg3
make_payload_symlink "$payload" usr/bin/awg-quick awg-quick3
build_fixture_package "$R2_REPOSITORY" "$payload" \
	amneziawg3-tools-aliases 3.1.20260812-r2 noarch amneziawg3-tools

payload="${LIFECYCLE_TMP}/payload-unrelated"
mkdir -p "$payload"
make_payload_file "$payload" usr/share/awg3-ci/unrelated-marker \
	'unrelated package must survive AWG3 upgrade' 0644
build_fixture_package "$R2_REPOSITORY" "$payload" \
	unrelated-fixture 1-r1 noarch ''
index_fixture_repository "$R2_REPOSITORY"

LEGACY_REPOSITORIES="${LIFECYCLE_TMP}/legacy-repositories.list"
R2_REPOSITORIES="${LIFECYCLE_TMP}/r2-repositories.list"
UPGRADE_REPOSITORIES="${LIFECYCLE_TMP}/upgrade-repositories.list"
{
	printf 'ndx file://%s/packages.adb\n' "$LEGACY_REPOSITORY"
	cat "$BASE_REPOSITORIES_FILE"
} > "$LEGACY_REPOSITORIES"
{
	printf 'ndx file://%s/packages.adb\n' "$R2_REPOSITORY"
	grep -Fvx "ndx file://${FEED_DIR}/packages.adb" \
		"$BASE_REPOSITORIES_FILE"
} > "$R2_REPOSITORIES"
{
	printf 'ndx file://%s/packages.adb\n' "$R2_REPOSITORY"
	cat "$BASE_REPOSITORIES_FILE"
} > "$UPGRADE_REPOSITORIES"

apk_root() {
	local root="$1"
	local repositories="$2"
	shift 2

	"$APK_TOOL" --root "$root" \
		--arch "$APK_ARCH" \
		--repositories-file "$repositories" \
		--allow-untrusted --cache=no "$@"
}

apk_root_no_scripts() {
	local root="$1"
	local repositories="$2"
	shift 2

	"$APK_TOOL" --root "$root" \
		--arch "$APK_ARCH" \
		--repositories-file "$repositories" \
		--allow-untrusted --cache=no --no-scripts "$@"
}

apk_init_root() {
	local root="$1"
	local repositories="$2"
	shift 2

	if [ "$(id -u)" -eq 0 ]; then
		apk_root_no_scripts "$root" "$repositories" add --initdb "$@"
	else
		apk_root_no_scripts "$root" "$repositories" \
			add --initdb --usermode "$@"
	fi
}

installed_manifest() {
	local root="$1"
	local output="$2"

	"$APK_TOOL" --root "$root" \
		--arch "$APK_ARCH" \
		--repositories-file /dev/null --no-network \
		list --manifest --installed | LC_ALL=C sort > "$output"
}

snapshot_root() {
	local root="$1"
	local output="$2"

	(
		cd "$root"
		find . -type d -print | LC_ALL=C sort | while IFS= read -r entry; do
			printf 'd\t%s\t%s\n' "$(stat -c '%a' "$entry")" "$entry"
		done
		find . \( -type f -o -type l \) -print | LC_ALL=C sort |
			while IFS= read -r entry; do
				if [ -L "$entry" ]; then
					printf 'l\t%s\t%s\n' "$(readlink "$entry")" "$entry"
				else
					printf 'f\t%s\t%s\t%s\n' \
						"$(stat -c '%a' "$entry")" \
						"$(sha256sum "$entry" | awk '{ print $1 }')" \
						"$entry"
				fi
			done
	) > "$output"
}

snapshot_selected_paths() {
	local root="$1"
	local output="$2"
	local pathname
	local entry
	shift 2

	for pathname do
		entry="${root}/${pathname}"
		if [ -L "$entry" ]; then
			printf 'l\t%s\t%s\n' "$(readlink "$entry")" "$pathname"
		elif [ -f "$entry" ]; then
			printf 'f\t%s\t%s\t%s\n' \
				"$(stat -c '%a' "$entry")" \
				"$(sha256sum "$entry" | awk '{ print $1 }')" \
				"$pathname"
		elif [ -d "$entry" ]; then
			printf 'd\t%s\t%s\n' "$(stat -c '%a' "$entry")" "$pathname"
		elif [ -e "$entry" ]; then
			printf 'o\t%s\t%s\n' "$(stat -c '%a' "$entry")" "$pathname"
		else
			printf 'm\t%s\n' "$pathname"
		fi
	done > "$output"
}

seed_network_state() {
	local root="$1"

	if [ ! -e "${root}/etc/config/network" ] &&
			[ ! -L "${root}/etc/config/network" ]; then
		make_payload_file "$root" etc/config/network \
			"config interface 'awg2_fixture'" 0600
	fi
	if [ ! -e "${root}/etc/config/firewall" ] &&
			[ ! -L "${root}/etc/config/firewall" ]; then
		make_payload_file "$root" etc/config/firewall \
			"config defaults 'fixture'" 0600
	fi
	if [ ! -e "${root}/etc/init.d/network" ] &&
			[ ! -L "${root}/etc/init.d/network" ]; then
		make_payload_file "$root" etc/init.d/network \
			'synthetic network lifecycle sentinel' 0755
	fi
	if [ ! -e "${root}/etc/init.d/amneziawg2" ] &&
			[ ! -L "${root}/etc/init.d/amneziawg2" ]; then
		make_payload_file "$root" etc/init.d/amneziawg2 \
			'synthetic AWG2 lifecycle sentinel' 0755
	fi
}

snapshot_lifecycle_state() {
	local root="$1"
	local prefix="$2"
	local full="${prefix}.root-full"

	installed_manifest "$root" "${prefix}.manifest"
	snapshot_root "$root" "$full"
	snapshot_selected_paths "$root" "${prefix}.world" \
		etc/apk/world
	awk -F '\t' '
		{
			path = $NF
			if (path == "./lib/apk/db/lock")
				next
			if (path == "./lib/apk/db" ||
					index(path, "./lib/apk/db/") == 1)
				print
		}
	' "$full" > "${prefix}.package-db"
	snapshot_selected_paths "$root" "${prefix}.payload" \
		usr/bin/amneziawg-go \
		usr/bin/awg \
		usr/bin/awg-quick \
		usr/bin/awg3 \
		usr/bin/awg-quick3 \
		usr/bin/amneziawg3_watchdog \
		usr/libexec/amneziawg3 \
		usr/libexec/amneziawg3/amneziawg3.init \
		usr/libexec/amneziawg3/amneziawg3-key-helper \
		usr/libexec/amneziawg3/awg \
		usr/libexec/amneziawg3/awg-quick \
		lib/netifd/proto/amneziawg3.sh \
		etc/amnezia/amneziawg3 \
		etc/amnezia/amneziawg3/upgrade-test.conf \
		usr/share/awg3-ci/unrelated-marker
	snapshot_selected_paths "$root" "${prefix}.init-network" \
		etc/config/network \
		etc/config/firewall \
		etc/init.d/network \
		etc/init.d/amneziawg2 \
		etc/init.d/amneziawg3 \
		lib/netifd/proto/amneziawg3.sh

	# APK commands may create only these non-lifecycle housekeeping paths:
	#   ./var/cache and the exact ./var/cache/apk subtree
	#   ./lib/apk/db/lock
	#   ./var/log/apk.log
	# Everything else remains part of the authoritative root snapshot.
	awk -F '\t' '
		function housekeeping(path) {
			return path == "./var/cache" ||
				path == "./var/cache/apk" ||
				index(path, "./var/cache/apk/") == 1 ||
				path == "./lib/apk/db/lock" ||
				path == "./var/log/apk.log"
		}
		{ path = $NF; if (!housekeeping(path)) print }
	' "$full" > "${prefix}.authoritative-root"
	awk -F '\t' '
		function housekeeping(path) {
			return path == "./var/cache" ||
				path == "./var/cache/apk" ||
				index(path, "./var/cache/apk/") == 1 ||
				path == "./lib/apk/db/lock" ||
				path == "./var/log/apk.log"
		}
		{ path = $NF; if (housekeeping(path)) print }
	' "$full" > "${prefix}.housekeeping"
}

append_sanitized_diff() {
	local before="$1"
	local after="$2"
	local output="${LIFECYCLE_TMP}/state.diff"

	diff -u "$before" "$after" > "$output" || true
	sed -e "s|${LIFECYCLE_TMP}|<TMP>|g" \
		-e "s|${FEED_DIR}|<FEED>|g" "$output"
}

assert_component_unchanged() {
	local case_name="$1"
	local component="$2"
	local before="$3"
	local after="$4"

	if ! cmp -s "$before" "$after"; then
		printf 'FAIL: %s changed authoritative component %s.\n' \
			"$case_name" "$component" >> "$REPORT_FILE"
		echo "$case_name changed authoritative component: $component" >&2
		append_sanitized_diff "$before" "$after" | tee -a "$REPORT_FILE" >&2
		exit 1
	fi
}

assert_unique_manifest() {
	local manifest="$1"
	local duplicates

	duplicates="$(awk '{ print $1 }' "$manifest" | LC_ALL=C sort | uniq -d)"
	[ -z "$duplicates" ] || {
		echo "Duplicate package records detected: $duplicates" >&2
		printf 'FAIL: duplicate package records: %s\n' "$duplicates" \
			>> "$REPORT_FILE"
		exit 1
	}
}

append_housekeeping_diff() {
	local before="$1"
	local after="$2"

	printf 'Allowed apk housekeeping changes:\n' >> "$REPORT_FILE"
	if cmp -s "$before" "$after"; then
		printf '  <none>\n' >> "$REPORT_FILE"
	else
		append_sanitized_diff "$before" "$after" |
			sed 's/^/  /' >> "$REPORT_FILE"
	fi
}

assert_lifecycle_state_unchanged() {
	local case_name="$1"
	local before="$2"
	local after="$3"
	local component

	for component in world package-db manifest payload init-network \
		authoritative-root; do
		assert_component_unchanged "$case_name" "$component" \
			"${before}.${component}" "${after}.${component}"
	done
	assert_unique_manifest "${after}.manifest"
	append_housekeeping_diff "${before}.housekeeping" \
		"${after}.housekeeping"
	printf '%s\n' \
		'Authoritative state: world, package DB, manifest, payload, symlinks, config, init, and network unchanged.' \
		>> "$REPORT_FILE"
}

append_state() {
	local label="$1"
	local root="$2"
	local manifest="${LIFECYCLE_TMP}/report-manifest"

	installed_manifest "$root" "$manifest"
	{
		printf '%s installed packages:\n' "$label"
		sed 's/^/  /' "$manifest"
		printf '%s world:\n' "$label"
		if [ -f "${root}/etc/apk/world" ]; then
			sed 's/^/  /' "${root}/etc/apk/world"
		else
			printf '  <missing>\n'
		fi
		printf '%s relevant files:\n' "$label"
		for pathname in \
			usr/bin/amneziawg-go \
			usr/bin/awg \
			usr/bin/awg-quick \
			usr/bin/awg3 \
			usr/bin/awg-quick3 \
			usr/bin/amneziawg3_watchdog \
			usr/libexec/amneziawg3/amneziawg3.init \
			usr/libexec/amneziawg3/amneziawg3-key-helper \
			usr/libexec/amneziawg3/awg \
			usr/libexec/amneziawg3/awg-quick \
			lib/netifd/proto/amneziawg3.sh \
			etc/config/network \
			etc/config/firewall \
			etc/init.d/amneziawg2 \
			etc/init.d/amneziawg3 \
			etc/amnezia/amneziawg3/upgrade-test.conf \
			usr/share/awg3-ci/unrelated-marker; do
			if [ -L "${root}/${pathname}" ]; then
				printf '  %s -> %s\n' "$pathname" \
					"$(readlink "${root}/${pathname}")"
			elif [ -f "${root}/${pathname}" ]; then
				printf '  %s  %s\n' \
					"$(sha256sum "${root}/${pathname}" | awk '{ print $1 }')" \
					"$pathname"
			fi
		done
	} >> "$REPORT_FILE"
}

append_command_log() {
	local logfile="$1"

	sed \
		-e "s|${LIFECYCLE_TMP}|<TMP>|g" \
		-e "s|${FEED_DIR}|<FEED>|g" \
		"$logfile" | sed 's/^/  /' >> "$REPORT_FILE"
}

assert_solver_conflict() {
	local logfile="$1"
	local expected_legacy
	local expected_awg3
	local pair_found=0
	shift

	grep -Eiq 'conflict|breaks|unable to select|unsatisfied' "$logfile" || {
		echo "APK solver failure did not identify a dependency conflict." >&2
		cat "$logfile" >&2
		exit 1
	}
	[ "$#" -ne 0 ] || return 0
	[ $(( $# % 2 )) -eq 0 ] || {
		echo 'Internal error: expected conflict pairs are incomplete.' >&2
		exit 2
	}
	while [ "$#" -ge 2 ]; do
		expected_legacy="$1"
		expected_awg3="$2"
		shift 2
		if grep -Fq "$expected_legacy" "$logfile" &&
				grep -Fq "$expected_awg3" "$logfile"; then
			pair_found=1
			break
		fi
	done
	[ "$pair_found" -eq 1 ] || {
		echo 'APK solver output did not identify any expected conflict pair.' >&2
		cat "$logfile" >&2
		exit 1
	}
}

assert_legacy_versions() {
	local manifest="$1"
	shift
	local package

	for package do
		case "$package" in
		amneziawg-go)
			grep -Fxq 'amneziawg-go 2.0-r7' "$manifest"
			;;
		amneziawg-tools)
			grep -Fxq 'amneziawg-tools 2.0-r7' "$manifest"
			;;
		*)
			echo "Unknown legacy fixture package: $package" >&2
			exit 2
			;;
		esac
	done
}

assert_awg3_versions() {
	local manifest="$1"
	shift
	local package

	for package do
		case "$package" in
		amneziawg3-go)
			grep -Fxq "amneziawg3-go ${GO_R3_VERSION}" "$manifest"
			;;
		amneziawg3-tools)
			grep -Fxq "amneziawg3-tools ${TOOLS_R3_VERSION}" "$manifest"
			;;
		amneziawg3-tools-aliases)
			grep -Fxq \
				"amneziawg3-tools-aliases ${ALIASES_R3_VERSION}" "$manifest"
			;;
		*)
			echo "Unknown AWG3 fixture package: $package" >&2
			exit 2
			;;
		esac
	done
}

assert_no_awg3_packages() {
	local manifest="$1"

	if grep -Eq '^amneziawg3([ -]|$)' "$manifest"; then
		echo 'A rejected transaction left an AWG3 package record.' >&2
		exit 1
	fi
}

assert_no_legacy_packages() {
	local manifest="$1"

	if grep -Eq '^amneziawg-(go|tools) ' "$manifest"; then
		echo 'A rejected reverse transaction left an AWG2 package record.' >&2
		exit 1
	fi
}

assert_no_awg3_namespaced_payload() {
	local root="$1"
	local pathname

	for pathname in \
		usr/bin/awg3 \
		usr/bin/awg-quick3 \
		usr/bin/amneziawg3_watchdog \
		usr/libexec/amneziawg3 \
		lib/netifd/proto/amneziawg3.sh \
		etc/init.d/amneziawg3 \
		etc/amnezia/amneziawg3; do
		if [ -e "${root}/${pathname}" ] || [ -L "${root}/${pathname}" ]; then
			echo "Rejected transaction introduced AWG3 payload: $pathname" >&2
			exit 1
		fi
	done
}

expect_forward_conflict() {
	local case_name="$1"
	local installed_packages="$2"
	local requested_packages="$3"
	local root="${LIFECYCLE_TMP}/forward-${case_name}/root"
	local before="${LIFECYCLE_TMP}/forward-${case_name}.before"
	local after="${LIFECYCLE_TMP}/forward-${case_name}.after"
	local logfile="${LIFECYCLE_TMP}/forward-${case_name}.log"
	local status
	shift 3

	mkdir -p "$root"
	# Fixture package names contain no whitespace; intentional word splitting.
	# shellcheck disable=SC2086
	apk_init_root "$root" "$LEGACY_REPOSITORIES" \
		$installed_packages >/dev/null
	seed_network_state "$root"
	snapshot_lifecycle_state "$root" "$before"
	{
		printf '\nFORWARD %s\n' "$case_name"
		printf 'Command: apk add %s\n' "$requested_packages"
	} >> "$REPORT_FILE"
	append_state Before "$root"

	set +e
	# shellcheck disable=SC2086
	apk_root "$root" "$LEGACY_REPOSITORIES" \
		add $requested_packages >"$logfile" 2>&1
	status=$?
	set -e
	[ "$status" -ne 0 ] || {
		echo "Forward lifecycle case unexpectedly succeeded: $case_name" >&2
		exit 1
	}
	assert_solver_conflict "$logfile" "$@"
	printf 'Exit: %s (expected non-zero)\nSolver output:\n' "$status" \
		>> "$REPORT_FILE"
	append_command_log "$logfile"
	snapshot_lifecycle_state "$root" "$after"
	assert_lifecycle_state_unchanged "FORWARD $case_name" "$before" "$after"
	# Fixture package names contain no whitespace; intentional word splitting.
	# shellcheck disable=SC2086
	assert_legacy_versions "${after}.manifest" $installed_packages
	assert_no_awg3_packages "${after}.manifest"
	assert_no_awg3_namespaced_payload "$root"
	case " $installed_packages " in
	*' amneziawg-go '*) ;;
	*) [ ! -e "${root}/usr/bin/amneziawg-go" ] ;;
	esac
	case " $installed_packages " in
	*' amneziawg-tools '*) ;;
	*)
		[ ! -e "${root}/usr/bin/awg" ]
		[ ! -e "${root}/usr/bin/awg-quick" ]
		;;
	esac
	append_state After "$root"
	printf 'Result: rejected atomically; all authoritative lifecycle snapshots match.\n' \
		>> "$REPORT_FILE"
}

expect_forward_conflict go-only \
	'amneziawg-go' 'amneziawg3-go' \
	amneziawg-go amneziawg3-go
expect_forward_conflict tools-only \
	'amneziawg-tools' 'amneziawg3-tools' \
	amneziawg-tools amneziawg3-tools
expect_forward_conflict both \
	'amneziawg-go amneziawg-tools' \
	'amneziawg3-go amneziawg3-tools' \
	amneziawg-go amneziawg3-go \
	amneziawg-tools amneziawg3-tools
expect_forward_conflict aliases \
	'amneziawg-tools' 'amneziawg3-tools-aliases' \
	amneziawg-tools amneziawg3-tools-aliases
expect_forward_conflict meta-package \
	'amneziawg-go amneziawg-tools' 'amneziawg3' \
	amneziawg-go amneziawg3-go \
	amneziawg-tools amneziawg3-tools

REVERSE_BASE="${LIFECYCLE_TMP}/reverse-base/root"
mkdir -p "$REVERSE_BASE"
apk_init_root "$REVERSE_BASE" "$LEGACY_REPOSITORIES" \
	amneziawg3-go amneziawg3-tools >/dev/null
seed_network_state "$REVERSE_BASE"
installed_manifest "$REVERSE_BASE" "${LIFECYCLE_TMP}/reverse-base.manifest"
grep -Fxq "amneziawg3-go ${GO_R3_VERSION}" \
	"${LIFECYCLE_TMP}/reverse-base.manifest"
grep -Fxq "amneziawg3-tools ${TOOLS_R3_VERSION}" \
	"${LIFECYCLE_TMP}/reverse-base.manifest"

REVERSE_ALIASES_BASE="${LIFECYCLE_TMP}/reverse-aliases-base/root"
mkdir -p "$REVERSE_ALIASES_BASE"
apk_init_root "$REVERSE_ALIASES_BASE" "$LEGACY_REPOSITORIES" \
	amneziawg3-go amneziawg3-tools amneziawg3-tools-aliases >/dev/null
seed_network_state "$REVERSE_ALIASES_BASE"
installed_manifest "$REVERSE_ALIASES_BASE" \
	"${LIFECYCLE_TMP}/reverse-aliases-base.manifest"
assert_awg3_versions "${LIFECYCLE_TMP}/reverse-aliases-base.manifest" \
	amneziawg3-go amneziawg3-tools amneziawg3-tools-aliases

expect_reverse_conflict() {
	local case_name="$1"
	local base_root="$2"
	local expected_packages="$3"
	local requested_packages="$4"
	local root="${LIFECYCLE_TMP}/reverse-${case_name}/root"
	local before="${LIFECYCLE_TMP}/reverse-${case_name}.before"
	local after="${LIFECYCLE_TMP}/reverse-${case_name}.after"
	local logfile="${LIFECYCLE_TMP}/reverse-${case_name}.log"
	local status
	shift 4

	mkdir -p "$(dirname "$root")"
	cp -a "$base_root" "$root"
	snapshot_lifecycle_state "$root" "$before"
	{
		printf '\nREVERSE %s\n' "$case_name"
		printf 'Command: apk add %s\n' "$requested_packages"
	} >> "$REPORT_FILE"
	append_state Before "$root"

	set +e
	# shellcheck disable=SC2086
	apk_root "$root" "$LEGACY_REPOSITORIES" \
		add $requested_packages >"$logfile" 2>&1
	status=$?
	set -e
	[ "$status" -ne 0 ] || {
		echo "Reverse lifecycle case unexpectedly succeeded: $case_name" >&2
		exit 1
	}
	assert_solver_conflict "$logfile" "$@"
	printf 'Exit: %s (expected non-zero)\nSolver output:\n' "$status" \
		>> "$REPORT_FILE"
	append_command_log "$logfile"
	snapshot_lifecycle_state "$root" "$after"
	assert_lifecycle_state_unchanged "REVERSE $case_name" "$before" "$after"
	# Fixture package names contain no whitespace; intentional word splitting.
	# shellcheck disable=SC2086
	assert_awg3_versions "${after}.manifest" $expected_packages
	assert_no_legacy_packages "${after}.manifest"
	append_state After "$root"
	printf 'Result: rejected atomically; all authoritative lifecycle snapshots match.\n' \
		>> "$REPORT_FILE"
}

expect_reverse_conflict go-only "$REVERSE_BASE" \
	'amneziawg3-go amneziawg3-tools' 'amneziawg-go' \
	amneziawg-go amneziawg3-go
expect_reverse_conflict tools-only "$REVERSE_BASE" \
	'amneziawg3-go amneziawg3-tools' 'amneziawg-tools' \
	amneziawg-tools amneziawg3-tools
expect_reverse_conflict aliases-collision "$REVERSE_ALIASES_BASE" \
	'amneziawg3-go amneziawg3-tools amneziawg3-tools-aliases' \
	'amneziawg-tools' \
	amneziawg-tools amneziawg3-tools-aliases \
	amneziawg-tools amneziawg3-tools
expect_reverse_conflict both "$REVERSE_BASE" \
	'amneziawg3-go amneziawg3-tools' \
	'amneziawg-go amneziawg-tools' \
	amneziawg-go amneziawg3-go \
	amneziawg-tools amneziawg3-tools

UPGRADE_ROOT="${LIFECYCLE_TMP}/upgrade/root"
mkdir -p "$UPGRADE_ROOT"
apk_init_root "$UPGRADE_ROOT" "$R2_REPOSITORIES" \
	bash ip-full kmod-tun netifd nftables-json resolveip \
	amneziawg3-go amneziawg3-tools \
	amneziawg3-tools-aliases unrelated-fixture >/dev/null
seed_network_state "$UPGRADE_ROOT"
mkdir -p "${UPGRADE_ROOT}/etc/amnezia/amneziawg3"
printf '%s\n' 'persistent fixture configuration' \
	> "${UPGRADE_ROOT}/etc/amnezia/amneziawg3/upgrade-test.conf"
chmod 0600 "${UPGRADE_ROOT}/etc/amnezia/amneziawg3/upgrade-test.conf"
CONFIG_HASH_BEFORE="$(sha256sum \
	"${UPGRADE_ROOT}/etc/amnezia/amneziawg3/upgrade-test.conf" |
	awk '{ print $1 }')"
SENTINEL_HASH_BEFORE="$(sha256sum \
	"${UPGRADE_ROOT}/usr/share/awg3-ci/unrelated-marker" |
	awk '{ print $1 }')"
R2_GO_HASH="$(sha256sum "${UPGRADE_ROOT}/usr/bin/amneziawg-go" |
	awk '{ print $1 }')"
R2_AWG_HASH="$(sha256sum "${UPGRADE_ROOT}/usr/bin/awg3" |
	awk '{ print $1 }')"
R2_QUICK_HASH="$(sha256sum "${UPGRADE_ROOT}/usr/bin/awg-quick3" |
	awk '{ print $1 }')"
cp "${UPGRADE_ROOT}/etc/apk/world" "${LIFECYCLE_TMP}/upgrade.world.before"
snapshot_selected_paths "$UPGRADE_ROOT" \
	"${LIFECYCLE_TMP}/upgrade.network.before" \
	etc/config/network etc/config/firewall etc/init.d/network \
	etc/init.d/amneziawg2 etc/init.d/amneziawg3
{
	printf '\nUPGRADE r2-to-r3\n'
	printf 'Command: apk upgrade amneziawg3-go amneziawg3-tools amneziawg3-tools-aliases\n'
} >> "$REPORT_FILE"
append_state Before "$UPGRADE_ROOT"
apk_root_no_scripts "$UPGRADE_ROOT" "$UPGRADE_REPOSITORIES" \
	upgrade amneziawg3-go amneziawg3-tools amneziawg3-tools-aliases \
	> "${LIFECYCLE_TMP}/upgrade.log" 2>&1
installed_manifest "$UPGRADE_ROOT" "${LIFECYCLE_TMP}/upgrade.manifest"
grep -Fxq "amneziawg3-go ${GO_R3_VERSION}" \
	"${LIFECYCLE_TMP}/upgrade.manifest"
grep -Fxq "amneziawg3-tools ${TOOLS_R3_VERSION}" \
	"${LIFECYCLE_TMP}/upgrade.manifest"
grep -Fxq "amneziawg3-tools-aliases ${ALIASES_R3_VERSION}" \
	"${LIFECYCLE_TMP}/upgrade.manifest"
grep -Fxq 'unrelated-fixture 1-r1' \
	"${LIFECYCLE_TMP}/upgrade.manifest"
assert_unique_manifest "${LIFECYCLE_TMP}/upgrade.manifest"
assert_no_legacy_packages "${LIFECYCLE_TMP}/upgrade.manifest"
cmp -s "${LIFECYCLE_TMP}/upgrade.world.before" \
	"${UPGRADE_ROOT}/etc/apk/world"
[ "$CONFIG_HASH_BEFORE" = "$(sha256sum \
	"${UPGRADE_ROOT}/etc/amnezia/amneziawg3/upgrade-test.conf" |
	awk '{ print $1 }')" ]
[ "$(stat -c '%a' \
	"${UPGRADE_ROOT}/etc/amnezia/amneziawg3/upgrade-test.conf")" = 600 ]
[ "$SENTINEL_HASH_BEFORE" = "$(sha256sum \
	"${UPGRADE_ROOT}/usr/share/awg3-ci/unrelated-marker" |
	awk '{ print $1 }')" ]
[ "$R2_GO_HASH" != "$(sha256sum \
	"${UPGRADE_ROOT}/usr/bin/amneziawg-go" | awk '{ print $1 }')" ]
[ "$R2_AWG_HASH" != "$(sha256sum \
	"${UPGRADE_ROOT}/usr/bin/awg3" | awk '{ print $1 }')" ]
[ "$R2_QUICK_HASH" != "$(sha256sum \
	"${UPGRADE_ROOT}/usr/bin/awg-quick3" | awk '{ print $1 }')" ]
[ -x "${UPGRADE_ROOT}/usr/bin/amneziawg-go" ]
[ -x "${UPGRADE_ROOT}/usr/bin/awg3" ]
[ -x "${UPGRADE_ROOT}/usr/bin/awg-quick3" ]
[ -x "${UPGRADE_ROOT}/usr/bin/amneziawg3_watchdog" ]
[ -x "${UPGRADE_ROOT}/lib/netifd/proto/amneziawg3.sh" ]
[ "$(readlink "${UPGRADE_ROOT}/usr/bin/awg")" = awg3 ]
[ "$(readlink "${UPGRADE_ROOT}/usr/bin/awg-quick")" = awg-quick3 ]
snapshot_selected_paths "$UPGRADE_ROOT" \
	"${LIFECYCLE_TMP}/upgrade.network.after" \
	etc/config/network etc/config/firewall etc/init.d/network \
	etc/init.d/amneziawg2 etc/init.d/amneziawg3
assert_component_unchanged 'UPGRADE r2-to-r3' init-network \
	"${LIFECYCLE_TMP}/upgrade.network.before" \
	"${LIFECYCLE_TMP}/upgrade.network.after"
append_command_log "${LIFECYCLE_TMP}/upgrade.log"
append_state After "$UPGRADE_ROOT"
printf 'Result: r2 fixtures upgraded to real r3 APKs; payload replaced; aliases correct; config, world, network state, and unrelated fixture preserved.\n' \
	>> "$REPORT_FILE"

snapshot_lifecycle_state "$UPGRADE_ROOT" "${LIFECYCLE_TMP}/repeat.before"
apk_root_no_scripts "$UPGRADE_ROOT" "$UPGRADE_REPOSITORIES" \
	add amneziawg3-go amneziawg3-tools amneziawg3-tools-aliases \
	> "${LIFECYCLE_TMP}/repeat-add.log" 2>&1
snapshot_lifecycle_state "$UPGRADE_ROOT" \
	"${LIFECYCLE_TMP}/repeat.after-add"
assert_lifecycle_state_unchanged 'REPEAT r3 apk add' \
	"${LIFECYCLE_TMP}/repeat.before" \
	"${LIFECYCLE_TMP}/repeat.after-add"
apk_root_no_scripts "$UPGRADE_ROOT" "$UPGRADE_REPOSITORIES" \
	upgrade amneziawg3-go amneziawg3-tools amneziawg3-tools-aliases \
	> "${LIFECYCLE_TMP}/repeat-upgrade.log" 2>&1
snapshot_lifecycle_state "$UPGRADE_ROOT" \
	"${LIFECYCLE_TMP}/repeat.after-upgrade"
assert_lifecycle_state_unchanged 'REPEAT r3 apk upgrade' \
	"${LIFECYCLE_TMP}/repeat.after-add" \
	"${LIFECYCLE_TMP}/repeat.after-upgrade"
assert_awg3_versions "${LIFECYCLE_TMP}/repeat.after-upgrade.manifest" \
	amneziawg3-go amneziawg3-tools amneziawg3-tools-aliases
assert_no_legacy_packages \
	"${LIFECYCLE_TMP}/repeat.after-upgrade.manifest"
[ "$(readlink "${UPGRADE_ROOT}/usr/bin/awg")" = awg3 ]
[ "$(readlink "${UPGRADE_ROOT}/usr/bin/awg-quick")" = awg-quick3 ]
{
	printf '\nREPEAT r3\n'
	printf 'Commands: apk add, then apk upgrade, for installed r3 packages\n'
	printf 'Result: both succeeded without changing authoritative package, world, payload, symlink, config, init, or network state.\n'
	printf '\nSUMMARY\n'
	printf 'Forward-AWG2-to-AWG3: verified\n'
	printf 'Partial-Transactions: rejected atomically\n'
	printf 'Reverse-AWG3-to-AWG2: verified\n'
	printf 'Reverse-Aliases-Collision: verified\n'
	printf 'Upgrade-r2-to-r3: verified\n'
	printf 'Repeated-r3-add-upgrade: verified\n'
	printf 'Housekeeping-Allowlist: ./var/cache, ./var/cache/apk/**, ./lib/apk/db/lock, ./var/log/apk.log only.\n'
	printf 'Package-Scripts: disabled while preparing/upgrading cross-architecture roots; conflict attempts ran normally and stopped before transaction.\n'
} >> "$REPORT_FILE"

echo "APK forward, reverse, partial, and upgrade lifecycle checks passed."
