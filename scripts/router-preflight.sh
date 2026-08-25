#!/bin/sh
# shellcheck disable=SC2009
set -eu

redact_uci() {
	sed -E \
		-e "s/(private_key|preshared_key|header_protection_key)='[^']*'/\1='<redacted>'/g" \
		-e 's/(private_key|preshared_key|header_protection_key)=[^ ]{1,}/\1=<redacted>/g' \
		-e "s/(endpoint_host|endpoint)='[^']*'/\1='<redacted-endpoint>'/g" \
		-e 's/(endpoint_host|endpoint)=[^ ]{1,}/\1=<redacted-endpoint>/g'
}

echo "== OpenWrt release =="
cat /etc/openwrt_release 2>/dev/null || true
uname -a

echo "== Device =="
cat /tmp/sysinfo/model 2>/dev/null || true
cat /tmp/sysinfo/board_name 2>/dev/null || true

echo "== Storage =="
df -h / /overlay 2>/dev/null || true

echo "== Package architecture and relevant packages =="
apk --print-arch 2>/dev/null || true
apk list --installed 2>/dev/null |
	grep -E '(^| )(amnezia|wireguard|luci-proto|kmod-tun)' || true

echo "== Relevant interfaces, with secrets redacted =="
uci -q show network 2>/dev/null |
	grep -E '(^network\..*proto=|amnezia|wireguard|private_key|preshared_key|header_protection_key)' |
	redact_uci || true

echo "== Relevant processes =="
ps w 2>/dev/null |
	grep -E '[a]mneziawg|[w]ireguard|[a]wg' || true

echo "== Existing command ownership =="
for path in /usr/bin/awg /usr/bin/awg-quick /usr/bin/awg3 /usr/bin/awg-quick3; do
	if [ -e "$path" ]; then
		ls -l "$path"
		apk info --who-owns "$path" 2>/dev/null || true
	fi
done

echo "Preflight is read-only. No configuration was changed."
