#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail

REPOSITORY_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/awg3-j-validation.XXXXXX")"
trap 'case "$TEST_TMP" in "${TMPDIR:-/tmp}"/awg3-j-validation.*) rm -rf -- "$TEST_TMP" ;; esac' EXIT

cd "$REPOSITORY_ROOT"

AWG3=/usr/bin/true
AWG3_GO=/usr/bin/true
AWG3_SOCKET_DIR="${TEST_TMP}/run"
INCLUDE_ONLY=1
TEST_PRIVATE_KEY='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
TEST_JC=4
TEST_JMIN=40
TEST_JMAX=70

config_value() {
	local key="$1:$2"
	local variable value

	case "$key" in
		awg3:private_key) variable=TEST_PRIVATE_KEY ;;
		awg3:jc) variable=TEST_JC ;;
		awg3:jmin) variable=TEST_JMIN ;;
		awg3:jmax) variable=TEST_JMAX ;;
		peer1:public_key)
			printf '%s' 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB='
			return 0
			;;
		*) return 1 ;;
	esac
	value="${!variable}"
	[[ "$value" != __ABSENT__ ]] || return 1
	printf '%s' "$value"
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

	[[ "$type" == amneziawg3_awg3 ]] && "$callback" peer1
}

source amneziawg-tools/files/amneziawg3.sh

load_values() {
	TEST_JC="$1"
	TEST_JMIN="$2"
	TEST_JMAX="$3"
	TEST_PRIVATE_KEY="${4:-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=}"
	awg3_load_interface_config awg3
}

assert_valid() {
	load_values "$1" "$2" "$3"
	if ! awg3_validate_config awg3; then
		printf 'Expected valid J tuple (%s, %s, %s), got %s.\n' \
			"$1" "$2" "$3" "$AWG3_VALIDATION_ERROR" >&2
		exit 1
	fi
}

assert_invalid() {
	local expected="$1"
	shift
	load_values "$1" "$2" "$3" "${4:-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=}"
	if awg3_validate_config awg3; then
		printf 'Expected %s for J tuple (%s, %s, %s).\n' \
			"$expected" "$1" "$2" "$3" >&2
		exit 1
	fi
	[[ "$AWG3_VALIDATION_ERROR" == "$expected" ]] || {
		printf 'Expected %s, got %s for J tuple (%s, %s, %s).\n' \
			"$expected" "$AWG3_VALIDATION_ERROR" "$1" "$2" "$3" >&2
		exit 1
	}
}

assert_valid __ABSENT__ __ABSENT__ __ABSENT__
assert_valid 1 0 1
assert_valid 128 1279 1280
assert_invalid JUNK_PARAMETERS_INCOMPLETE __ABSENT__ 10 __ABSENT__
assert_invalid JUNK_PARAMETERS_INCOMPLETE __ABSENT__ __ABSENT__ 50
assert_invalid INVALID_JUNK_RANGE 4 70 40
assert_invalid INVALID_JUNK_RANGE 4 40 40
assert_invalid INVALID_JC 0 0 1
assert_invalid INVALID_JC 129 0 1
assert_invalid INVALID_JMIN 1 1280 1280
assert_invalid INVALID_JMAX 1 0 1281
assert_invalid INVALID_JC 65535 0 1
assert_invalid INVALID_JMIN 1 65535 65535
assert_invalid INVALID_JMAX 1 0 65535
assert_invalid INVALID_JC nope 0 1
assert_invalid INVALID_JMIN 1 -1 2
assert_invalid INVALID_JMAX 1 0 01
assert_invalid KEY_MUST_BE_PERSISTED 4 40 70 generate

saved_budget="$AWG3_JUNK_ALLOCATION_BUDGET"
AWG3_JUNK_ALLOCATION_BUDGET=99
assert_invalid JUNK_MEMORY_BUDGET_EXCEEDED 2 0 50
AWG3_JUNK_ALLOCATION_BUDGET="$saved_budget"

# A bad tuple must fail before the helper asks the OS about a link or starts a
# daemon. These mocks are deliberately observable.
: > "${TEST_TMP}/network-calls"
config_load() { :; }
logger() { :; }
proto_notify_error() { :; }
proto_setup_failed() { :; }
ip() { printf 'ip\n' >> "${TEST_TMP}/network-calls"; return 1; }
proto_run_command() { printf 'daemon\n' >> "${TEST_TMP}/network-calls"; }

load_values 4 70 40
if proto_amneziawg3_setup awg3; then
	echo 'Invalid J tuple unexpectedly reached setup success.' >&2
	exit 1
fi
[[ ! -s "${TEST_TMP}/network-calls" ]] || {
	echo 'Invalid J tuple touched the link or daemon before validation.' >&2
	exit 1
}

if rg -n '(^|[;&|[:space:]])uci[[:space:]]+(set|commit|batch|import)' \
		amneziawg-tools/files/amneziawg3.sh >/dev/null; then
	echo 'The netifd helper must not persist or commit a generated key.' >&2
	exit 1
fi

echo 'J-parameter validation tests passed.'
