#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2016-2017 Dan Luedtke <mail@danrl.com>
# Copyright 2026 AWG OpenWrt3 contributors
# Configuration variables are populated dynamically by OpenWrt config_get.
# shellcheck disable=SC1091,SC2034,SC2154,SC2317,SC3043

AWG3="${AWG3:-/usr/libexec/amneziawg3/awg}"
AWG3_GO="${AWG3_GO:-/usr/bin/amneziawg-go}"
AWG3_SOCKET_DIR="${AWG3_SOCKET_DIR:-/var/run/amneziawg}"
AWG3_CARRIAGE_RETURN="$(printf '\r')"
AWG3_JC_MAX=128
AWG3_JMIN_MAX=1279
AWG3_JMAX_MAX=1280
AWG3_JUNK_ALLOCATION_BUDGET=163840

if [ ! -x "$AWG3" ] || [ ! -x "$AWG3_GO" ]; then
	logger -t amneziawg3 "error: required AmneziaWG 3.1 binaries are missing"
	exit 0
fi

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

proto_amneziawg3_init_config() {
	renew_handler=1
	peer_detect=1

	proto_config_add_string "private_key"
	proto_config_add_int "listen_port"
	proto_config_add_int "mtu"
	proto_config_add_string "fwmark"
	proto_config_add_string "address"
	proto_config_add_string "addresses"
	proto_config_add_string "ip6prefix"
	proto_config_add_boolean "nohostroute"
	proto_config_add_string "tunlink"

	proto_config_add_int "jc"
	proto_config_add_int "jmin"
	proto_config_add_int "jmax"
	proto_config_add_int "s1"
	proto_config_add_int "s2"
	proto_config_add_int "s3"
	proto_config_add_int "s4"
	proto_config_add_string "h1"
	proto_config_add_string "h2"
	proto_config_add_string "h3"
	proto_config_add_string "h4"
	proto_config_add_string "i1"
	proto_config_add_string "i2"
	proto_config_add_string "i3"
	proto_config_add_string "i4"
	proto_config_add_string "i5"
	proto_config_add_string "header_protection_key"
	proto_config_add_string "content_padding_addition"
	proto_config_add_string "rekey_after_time"
	proto_config_add_string "rekey_timeout"
	proto_config_add_string "reject_after_time"
	proto_config_add_string "keepalive_timeout"
	proto_config_add_string "max_handshake_attempts"
	proto_config_add_boolean "random_trailers"
	proto_config_add_boolean "disable_cookies"

	available=1
}

awg3_fail() {
	local config="$1"
	local code="$2"
	local message="$3"

	logger -t amneziawg3 "error: ${config}: ${message}"
	proto_notify_error "$config" "$code"
	proto_setup_failed "$config"
	return 1
}

awg3_valid_interface_name() {
	local name="$1"

	[ -n "$name" ] || return 1
	case "$name" in
		*[!A-Za-z0-9_=+.-]*|????????????????*) return 1 ;;
	esac
	return 0
}

awg3_value_is_single_line() {
	case "$1" in
		*"
"*|*"${AWG3_CARRIAGE_RETURN}"*) return 1 ;;
	esac
	return 0
}

awg3_load_interface_config() {
	local config="$1"

	config_get private_key "$config" private_key
	config_get listen_port "$config" listen_port
	config_get mtu "$config" mtu
	config_get fwmark "$config" fwmark
	config_get address "$config" address
	config_get addresses "$config" addresses
	config_get ip6prefix "$config" ip6prefix
	config_get_bool nohostroute "$config" nohostroute 0
	config_get tunlink "$config" tunlink

	config_get jc "$config" jc
	config_get jmin "$config" jmin
	config_get jmax "$config" jmax
	config_get s1 "$config" s1
	config_get s2 "$config" s2
	config_get s3 "$config" s3
	config_get s4 "$config" s4
	config_get h1 "$config" h1
	config_get h2 "$config" h2
	config_get h3 "$config" h3
	config_get h4 "$config" h4
	config_get i1 "$config" i1
	config_get i2 "$config" i2
	config_get i3 "$config" i3
	config_get i4 "$config" i4
	config_get i5 "$config" i5
	config_get header_protection_key "$config" header_protection_key
	config_get content_padding_addition "$config" content_padding_addition
	config_get rekey_after_time "$config" rekey_after_time
	config_get rekey_timeout "$config" rekey_timeout
	config_get reject_after_time "$config" reject_after_time
	config_get keepalive_timeout "$config" keepalive_timeout
	config_get max_handshake_attempts "$config" max_handshake_attempts
	config_get_bool random_trailers "$config" random_trailers 0
	config_get_bool disable_cookies "$config" disable_cookies 0

	[ -z "$address" ] || addresses="${addresses:+${addresses} }${address}"
}

awg3_parse_bounded_uint() {
	local input="$1"
	local maximum="$2"

	case "$input" in
		0) ;;
		0*|*[!0-9]*) return 1 ;;
	esac
	[ "${#input}" -le "${#maximum}" ] || return 1
	[ "$input" -le "$maximum" ] || return 1
	AWG3_PARSED_UINT="$input"
}

awg3_validate_junk_parameters() {
	local present=0
	local parsed_jc parsed_jmin parsed_jmax

	[ -z "$jc" ] || present=$((present + 1))
	[ -z "$jmin" ] || present=$((present + 1))
	[ -z "$jmax" ] || present=$((present + 1))
	[ "$present" -ne 0 ] || return 0
	if [ "$present" -ne 3 ]; then
		AWG3_VALIDATION_ERROR=JUNK_PARAMETERS_INCOMPLETE
		return 1
	fi

	if ! awg3_parse_bounded_uint "$jc" "$AWG3_JC_MAX" ||
		[ "$AWG3_PARSED_UINT" -lt 1 ]; then
		AWG3_VALIDATION_ERROR=INVALID_JC
		return 1
	fi
	parsed_jc="$AWG3_PARSED_UINT"

	if ! awg3_parse_bounded_uint "$jmin" "$AWG3_JMIN_MAX"; then
		AWG3_VALIDATION_ERROR=INVALID_JMIN
		return 1
	fi
	parsed_jmin="$AWG3_PARSED_UINT"

	if ! awg3_parse_bounded_uint "$jmax" "$AWG3_JMAX_MAX" ||
		[ "$AWG3_PARSED_UINT" -lt 1 ]; then
		AWG3_VALIDATION_ERROR=INVALID_JMAX
		return 1
	fi
	parsed_jmax="$AWG3_PARSED_UINT"

	if [ "$parsed_jmin" -ge "$parsed_jmax" ]; then
		AWG3_VALIDATION_ERROR=INVALID_JUNK_RANGE
		return 1
	fi
	if [ $((parsed_jc * parsed_jmax)) -gt "$AWG3_JUNK_ALLOCATION_BUDGET" ]; then
		AWG3_VALIDATION_ERROR=JUNK_MEMORY_BUDGET_EXCEEDED
		return 1
	fi
}

awg3_validate_peer() {
	local section="$1"
	local disabled public_key preshared_key allowed_ips
	local endpoint_host endpoint_port persistent_keepalive value

	config_get_bool disabled "$section" disabled 0
	[ "$disabled" -eq 0 ] || return 0
	config_get public_key "$section" public_key
	config_get preshared_key "$section" preshared_key
	config_get allowed_ips "$section" allowed_ips
	config_get endpoint_host "$section" endpoint_host
	config_get endpoint_port "$section" endpoint_port
	config_get persistent_keepalive "$section" persistent_keepalive

	for value in "$public_key" "$preshared_key" "$allowed_ips" \
		"$endpoint_host" "$endpoint_port" "$persistent_keepalive"; do
		if ! awg3_value_is_single_line "$value"; then
			AWG3_INVALID_PEER="$section"
			AWG3_VALIDATION_ERROR=MULTILINE_VALUE
			return 0
		fi
	done
	if [ -z "$public_key" ]; then
		AWG3_INVALID_PEER="$section"
	fi
}

awg3_validate_config() {
	local config="$1"
	local value

	AWG3_INVALID_PEER=
	AWG3_VALIDATION_ERROR=

	if [ -z "$private_key" ]; then
		AWG3_VALIDATION_ERROR=MISSING_PRIVATE_KEY
		return 1
	fi
	if [ "$private_key" = "generate" ]; then
		AWG3_VALIDATION_ERROR=KEY_MUST_BE_PERSISTED
		return 1
	fi

	for value in "$private_key" "$listen_port" "$mtu" "$fwmark" \
		"$addresses" "$ip6prefix" "$tunlink" "$jc" "$jmin" "$jmax" \
		"$s1" "$s2" "$s3" "$s4" "$h1" "$h2" "$h3" "$h4" \
		"$i1" "$i2" "$i3" "$i4" "$i5" "$header_protection_key" \
		"$content_padding_addition" "$rekey_after_time" "$rekey_timeout" \
		"$reject_after_time" "$keepalive_timeout" \
		"$max_handshake_attempts"; do
		if ! awg3_value_is_single_line "$value"; then
			AWG3_VALIDATION_ERROR=MULTILINE_VALUE
			return 1
		fi
	done

	awg3_validate_junk_parameters || return 1

	config_foreach awg3_validate_peer "amneziawg3_${config}"
	[ "$AWG3_VALIDATION_ERROR" != "MULTILINE_VALUE" ] || return 1
	if [ -n "$AWG3_INVALID_PEER" ]; then
		AWG3_VALIDATION_ERROR=MISSING_PEER_PUBLIC_KEY
		return 1
	fi
	AWG3_VALIDATION_ERROR=
}

awg3_report_validation_error() {
	local config="$1"

	case "$AWG3_VALIDATION_ERROR" in
		MISSING_PRIVATE_KEY)
			awg3_fail "$config" MISSING_PRIVATE_KEY "private_key is required"
			;;
		KEY_MUST_BE_PERSISTED)
			awg3_fail "$config" KEY_MUST_BE_PERSISTED \
				"private_key=generate is unsupported; generate and save the key before ifup"
			;;
		JUNK_PARAMETERS_INCOMPLETE)
			awg3_fail "$config" JUNK_PARAMETERS_INCOMPLETE \
				"jc, jmin, and jmax must be either all present or all absent"
			;;
		INVALID_JC)
			awg3_fail "$config" INVALID_JC \
				"jc must be a decimal integer from 1 to 128"
			;;
		INVALID_JMIN)
			awg3_fail "$config" INVALID_JMIN \
				"jmin must be a decimal integer from 0 to 1279"
			;;
		INVALID_JMAX)
			awg3_fail "$config" INVALID_JMAX \
				"jmax must be a decimal integer from 1 to 1280"
			;;
		INVALID_JUNK_RANGE)
			awg3_fail "$config" INVALID_JUNK_RANGE \
				"jmin must be strictly less than jmax"
			;;
		JUNK_MEMORY_BUDGET_EXCEEDED)
			awg3_fail "$config" JUNK_MEMORY_BUDGET_EXCEEDED \
				"jc multiplied by jmax exceeds the 163840-byte allocation budget"
			;;
		MISSING_PEER_PUBLIC_KEY)
			awg3_fail "$config" MISSING_PEER_PUBLIC_KEY \
				"peer ${AWG3_INVALID_PEER} has no public_key"
			;;
		MULTILINE_VALUE)
			awg3_fail "$config" MULTILINE_VALUE \
				"configuration values must not contain line breaks"
			;;
		*)
			awg3_fail "$config" INVALID_CONFIGURATION \
				"configuration validation failed"
			;;
	esac
}

awg3_emit_optional() {
	local key="$1"
	local value="$2"

	[ -z "$value" ] || printf '%s=%s\n' "$key" "$value"
}

awg3_emit_peer() {
	local section="$1"
	local disabled public_key preshared_key allowed_ips
	local endpoint_host endpoint_port persistent_keepalive
	local allowed_ip separator

	config_get_bool disabled "$section" disabled 0
	[ "$disabled" -eq 0 ] || return 0
	config_get public_key "$section" public_key
	config_get preshared_key "$section" preshared_key
	config_get allowed_ips "$section" allowed_ips
	config_get endpoint_host "$section" endpoint_host
	config_get endpoint_port "$section" endpoint_port 51820
	config_get persistent_keepalive "$section" persistent_keepalive

	printf '\n[Peer]\n'
	printf 'PublicKey=%s\n' "$public_key"
	awg3_emit_optional PresharedKey "$preshared_key"
	if [ -n "$allowed_ips" ]; then
		printf 'AllowedIPs='
		separator=
		for allowed_ip in $allowed_ips; do
			printf '%s%s' "$separator" "$allowed_ip"
			separator=", "
		done
		printf '\n'
	fi
	if [ -n "$endpoint_host" ]; then
		case "$endpoint_host" in
			\[*\]) ;;
			*:*) endpoint_host="[${endpoint_host}]" ;;
		esac
		printf 'Endpoint=%s:%s\n' "$endpoint_host" "${endpoint_port:-51820}"
	fi
	awg3_emit_optional PersistentKeepalive "$persistent_keepalive"
}

awg3_emit_config() {
	local config="$1"

	printf '[Interface]\n'
	printf 'PrivateKey=%s\n' "$private_key"
	awg3_emit_optional ListenPort "$listen_port"
	awg3_emit_optional FwMark "$fwmark"
	awg3_emit_optional Jc "$jc"
	awg3_emit_optional Jmin "$jmin"
	awg3_emit_optional Jmax "$jmax"
	awg3_emit_optional S1 "$s1"
	awg3_emit_optional S2 "$s2"
	awg3_emit_optional S3 "$s3"
	awg3_emit_optional S4 "$s4"
	awg3_emit_optional H1 "$h1"
	awg3_emit_optional H2 "$h2"
	awg3_emit_optional H3 "$h3"
	awg3_emit_optional H4 "$h4"
	awg3_emit_optional I1 "$i1"
	awg3_emit_optional I2 "$i2"
	awg3_emit_optional I3 "$i3"
	awg3_emit_optional I4 "$i4"
	awg3_emit_optional I5 "$i5"
	awg3_emit_optional HeaderProtectionKey "$header_protection_key"
	awg3_emit_optional ContentPaddingAddition "$content_padding_addition"
	awg3_emit_optional RekeyAfterTime "$rekey_after_time"
	awg3_emit_optional RekeyTimeout "$rekey_timeout"
	awg3_emit_optional RejectAfterTime "$reject_after_time"
	awg3_emit_optional KeepaliveTimeout "$keepalive_timeout"
	awg3_emit_optional MaxHandshakeAttempts "$max_handshake_attempts"
	awg3_emit_optional RandomTrailers "$random_trailers"
	awg3_emit_optional DisableCookies "$disable_cookies"
	config_foreach awg3_emit_peer "amneziawg3_${config}"
}

awg3_add_peer_routes() {
	local section="$1"
	local disabled route_allowed_ips allowed_ips allowed_ip

	config_get_bool disabled "$section" disabled 0
	config_get_bool route_allowed_ips "$section" route_allowed_ips 0
	[ "$disabled" -eq 0 ] || return 0
	[ "$route_allowed_ips" -ne 0 ] || return 0
	config_get allowed_ips "$section" allowed_ips

	for allowed_ip in $allowed_ips; do
		case "$allowed_ip" in
			*:*"/"*) proto_add_ipv6_route "${allowed_ip%%/*}" "${allowed_ip##*/}" ;;
			*.*"/"*) proto_add_ipv4_route "${allowed_ip%%/*}" "${allowed_ip##*/}" ;;
			*:*) proto_add_ipv6_route "$allowed_ip" 128 ;;
			*.*) proto_add_ipv4_route "$allowed_ip" 32 ;;
		esac
	done
}

awg3_add_addresses() {
	local configured_address

	for configured_address in $addresses; do
		case "$configured_address" in
			*:*"/"*)
				proto_add_ipv6_address \
					"${configured_address%%/*}" "${configured_address##*/}"
				;;
			*.*"/"*)
				proto_add_ipv4_address \
					"${configured_address%%/*}" "${configured_address##*/}"
				;;
			*:*) proto_add_ipv6_address "$configured_address" 128 ;;
			*.*) proto_add_ipv4_address "$configured_address" 32 ;;
		esac
	done

	for configured_address in $ip6prefix; do
		proto_add_ipv6_prefix "$configured_address"
	done
}

awg3_add_endpoint_dependencies() {
	local config="$1"

	[ "$nohostroute" = "1" ] && return 0
	"$AWG3" show "$config" endpoints 2>/dev/null |
		sed -E 's/\[?([0-9.:a-fA-F]+)\]?:([0-9]+)/\1 \2/' |
		while read -r public_key endpoint port; do
			[ -n "$public_key" ] || continue
			[ -n "$port" ] || continue
			proto_add_host_dependency "$config" "$endpoint" "$tunlink"
		done
}

awg3_apply_config() {
	local config="$1"

	config_load network
	awg3_load_interface_config "$config"
	awg3_validate_config "$config" || return 1

	proto_init_update "$config" 1
	awg3_emit_config "$config" |
		"$AWG3" syncconf "$config" /dev/stdin ||
		return 1

	if [ -n "$mtu" ]; then
		ip link set mtu "$mtu" dev "$config" || return 1
	fi
	awg3_add_addresses
	config_foreach awg3_add_peer_routes "amneziawg3_${config}"
	awg3_add_endpoint_dependencies "$config"
	proto_send_update "$config"
}

awg3_wait_until_ready() {
	local config="$1"
	local attempt=0

	while [ "$attempt" -lt 10 ]; do
		"$AWG3" show "$config" >/dev/null 2>&1 && return 0
		sleep 1
		attempt=$((attempt + 1))
	done
	return 1
}

proto_amneziawg3_setup() {
	local config="$1"
	local socket="${AWG3_SOCKET_DIR}/${config}.sock"

	if ! awg3_valid_interface_name "$config"; then
		awg3_fail "$config" INVALID_INTERFACE_NAME \
			"interface name must contain at most 15 safe characters"
		return 1
	fi

	config_load network
	awg3_load_interface_config "$config"
	if ! awg3_validate_config "$config"; then
		awg3_report_validation_error "$config"
		return 1
	fi

	if ip link show dev "$config" >/dev/null 2>&1; then
		awg3_fail "$config" INTERFACE_ALREADY_EXISTS \
			"refusing to reuse a pre-existing network interface"
		return 1
	fi
	if [ -e "$socket" ]; then
		awg3_fail "$config" UAPI_SOCKET_ALREADY_EXISTS \
			"refusing to remove a pre-existing UAPI socket"
		return 1
	fi

	proto_run_command "$config" "$AWG3_GO" -f "$config"
	if ! awg3_wait_until_ready "$config"; then
		proto_kill_command "$config" 15
		awg3_fail "$config" USERSPACE_NOT_READY \
			"userspace daemon did not become ready"
		return 1
	fi

	if ! awg3_apply_config "$config"; then
		proto_kill_command "$config" 15
		awg3_fail "$config" CONFIGURATION_FAILED \
			"configuration could not be applied"
		return 1
	fi
}

proto_amneziawg3_renew() {
	local config="$1"

	if ! "$AWG3" show "$config" >/dev/null 2>&1; then
		proto_notify_error "$config" USERSPACE_NOT_READY
		logger -t amneziawg3 \
			"error: ${config}: cannot renew an interface that is not ready"
		return 1
	fi
	if ! awg3_apply_config "$config"; then
		proto_notify_error "$config" CONFIGURATION_FAILED
		logger -t amneziawg3 \
			"error: ${config}: renewed configuration could not be applied completely"
		return 1
	fi
}

proto_amneziawg3_teardown() {
	local config="$1"

	proto_kill_command "$config" 15
}

[ -n "$INCLUDE_ONLY" ] || add_protocol amneziawg3
