#!/bin/sh
# shellcheck disable=SC3043
set -eu
umask 022

# Capture and immediately remove the GitHub secret from the exported
# environment. The replacement shell variable is not exported to SDK tools or
# package build processes.
AWG3_SIGNING_KEY_B64="${AWG3_APK_PRIVATE_KEY_B64:-}"
unset AWG3_APK_PRIVATE_KEY_B64

case "${AWG3_REQUIRE_SIGNING_KEY:-0}" in
	0)
		[ -z "$AWG3_SIGNING_KEY_B64" ] || {
			echo "Refusing a signing secret in an unsigned CI build." >&2
			exit 1
		}
		AWG3_FEED_SIGNING_STATUS=unsigned-test
		;;
	1)
		[ -n "$AWG3_SIGNING_KEY_B64" ] || {
			echo "AWG3_APK_PRIVATE_KEY_B64 is required for a release build." >&2
			exit 1
		}
		AWG3_FEED_SIGNING_STATUS=signed-release
		;;
	*)
		echo "AWG3_REQUIRE_SIGNING_KEY must be either 0 or 1." >&2
		exit 1
		;;
esac

OPENWRT_VERSION=25.12.5
OPENWRT_TARGET=mediatek
OPENWRT_SUBTARGET=filogic
OPENWRT_ARCH=aarch64_cortex-a53
SDK_ARCHIVE=openwrt-sdk-25.12.5-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64.tar.zst
SDK_SHA256=ff4a38a397caa2cfe1c39e18f84ddede14878221b3593c3f2c4cfe24e3ec4c25
AWG_GO_VERSION=3.1.20260814
AWG_GO_SHA256=c146a640c18468caac71fd158c02a94afcf6beadb5fd585c092bf55cbdefdbff
AWG_TOOLS_VERSION=3.1.20260812
AWG_TOOLS_SHA256=dbd8ce0748d835d18f30bb76720246b7bfc80bd09cd17c379b1c59f683a18493
APK_PRIVATE_KEY=private-key.pem
APK_PUBLIC_KEY=public-key.pem

REPOSITORY_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT_DIR="${REPOSITORY_ROOT}/dist"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/awg3-sdk.XXXXXX")"
chmod 0700 "$BUILD_ROOT"
trap 'case "$BUILD_ROOT" in "${TMPDIR:-/tmp}"/awg3-sdk.*) rm -rf -- "$BUILD_ROOT" ;; esac' EXIT

if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
	echo "The official SDK requires an x86_64 Linux build host." >&2
	exit 1
fi

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
	sha256sum "$1" | awk '{ print $1 }'
}

SDK_PATH="${BUILD_ROOT}/${SDK_ARCHIVE}"
SDK_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${OPENWRT_TARGET}/${OPENWRT_SUBTARGET}/${SDK_ARCHIVE}"
download "$SDK_URL" "$SDK_PATH"

if [ "$(hash_file "$SDK_PATH")" != "$SDK_SHA256" ]; then
	echo "OpenWrt SDK checksum verification failed." >&2
	exit 1
fi

tar --zstd -xf "$SDK_PATH" -C "$BUILD_ROOT"
SDK_DIR="$(find "$BUILD_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'openwrt-sdk-*' -print -quit)"
[ -n "$SDK_DIR" ] || {
	echo "OpenWrt SDK directory was not found after extraction." >&2
	exit 1
}

ln -s "$REPOSITORY_ROOT" "${BUILD_ROOT}/awg3-source"
printf '\nsrc-link awg3 %s\n' "${BUILD_ROOT}/awg3-source" >> "${SDK_DIR}/feeds.conf.default"

cd "$SDK_DIR"
./scripts/feeds update -a
./scripts/feeds install -a

cat >> .config <<'CONFIG'
CONFIG_PACKAGE_amneziawg3-go=m
CONFIG_PACKAGE_amneziawg3-tools=m
CONFIG_PACKAGE_amneziawg3-tools-aliases=m
CONFIG_PACKAGE_luci-proto-amneziawg3=m
CONFIG_PACKAGE_amneziawg3=m
CONFIG

if [ "$AWG3_FEED_SIGNING_STATUS" = signed-release ]; then
	printf '%s\n' 'CONFIG_SIGNED_PACKAGES=y' >> .config
fi

make defconfig
JOBS="${AWG3_BUILD_JOBS:-$(nproc)}"
make -j"$JOBS" \
	package/feeds/awg3/amneziawg-go/compile \
	package/feeds/awg3/amneziawg-tools/compile \
	package/feeds/awg3/amneziawg-tools-aliases/compile \
	package/feeds/awg3/luci-proto-amneziawg3/compile \
	package/feeds/awg3/amneziawg3/compile

if [ "$AWG3_FEED_SIGNING_STATUS" = signed-release ]; then
	(
		umask 077
		printf '%s' "$AWG3_SIGNING_KEY_B64" | base64 -d > "$APK_PRIVATE_KEY"
		chmod 0600 "$APK_PRIVATE_KEY"
	)
	AWG3_SIGNING_KEY_B64=
	unset AWG3_SIGNING_KEY_B64
	openssl ec -in "$APK_PRIVATE_KEY" -check -noout 2>/dev/null
	APK_KEY_CURVE="$(openssl ec -in "$APK_PRIVATE_KEY" -param_out 2>/dev/null |
		openssl ecparam -text -noout 2>/dev/null |
		sed -n 's/^ASN1 OID: //p')"
	[ "$APK_KEY_CURVE" = "prime256v1" ] || {
		echo "APK signing key must use the prime256v1 (P-256) curve." >&2
		exit 1
	}
	openssl ec -in "$APK_PRIVATE_KEY" -pubout -out "$APK_PUBLIC_KEY" 2>/dev/null
fi

make package/index

if [ "$AWG3_FEED_SIGNING_STATUS" = signed-release ]; then
	[ -s "$APK_PUBLIC_KEY" ] || {
		echo "APK feed public key was not produced." >&2
		exit 1
	}
	rm -f -- "$APK_PRIVATE_KEY"
fi

FEED_DIR="$(find "bin/packages/${OPENWRT_ARCH}" -mindepth 1 -maxdepth 1 \
	-type d -name awg3 -print -quit)"
if [ -z "$FEED_DIR" ] || [ ! -f "${FEED_DIR}/packages.adb" ]; then
	echo "AWG3 package index was not produced." >&2
	exit 1
fi
set -- "${FEED_DIR}"/*.apk
if [ "$#" -ne 5 ] || [ ! -f "$1" ]; then
	echo "Expected exactly five AWG3 APK files, found $# entries." >&2
	exit 1
fi

APK_REPORT_DIR="${BUILD_ROOT}/apk-reports"
"${REPOSITORY_ROOT}/scripts/verify-apk-feed.sh" \
	"${SDK_DIR}/staging_dir/host/bin/apk" \
	"$FEED_DIR" \
	"$APK_REPORT_DIR" \
	"$AWG3_FEED_SIGNING_STATUS" \
	"$(if [ "$AWG3_FEED_SIGNING_STATUS" = signed-release ]; then printf '%s' "${SDK_DIR}/${APK_PUBLIC_KEY}"; fi)"

mkdir -p "$OUTPUT_DIR"
find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 \
	\( -name '*.apk' -o -name 'packages.adb' -o -name 'SHA256SUMS' \
	-o -name 'build-info.txt' -o -name 'awg-openwrt3.pem' \
	-o -name 'feed-index.json' -o -name 'package-metadata.json' \
	-o -name 'installed-files.txt' -o -name 'solver-plan.txt' \
	-o -name 'verification-summary.txt' \) -delete
cp "${FEED_DIR}"/*.apk "${FEED_DIR}/packages.adb" "$OUTPUT_DIR/"
cp "${APK_REPORT_DIR}"/* "$OUTPUT_DIR/"
if [ "$AWG3_FEED_SIGNING_STATUS" = signed-release ]; then
	cp "$APK_PUBLIC_KEY" "${OUTPUT_DIR}/awg-openwrt3.pem"
fi

SOURCE_REVISION="$(git -C "$REPOSITORY_ROOT" rev-parse HEAD 2>/dev/null || printf '%s' working-tree)"
cat > "${OUTPUT_DIR}/build-info.txt" <<EOF
OpenWrt-Version: ${OPENWRT_VERSION}
OpenWrt-Target: ${OPENWRT_TARGET}/${OPENWRT_SUBTARGET}
OpenWrt-Architecture: ${OPENWRT_ARCH}
SDK-Archive: ${SDK_ARCHIVE}
SDK-SHA256: ${SDK_SHA256}
AmneziaWG-Go-Version: ${AWG_GO_VERSION}
AmneziaWG-Go-Source-SHA256: ${AWG_GO_SHA256}
AmneziaWG-Tools-Version: ${AWG_TOOLS_VERSION}
AmneziaWG-Tools-Source-SHA256: ${AWG_TOOLS_SHA256}
Feed-Signing: ${AWG3_FEED_SIGNING_STATUS}
Source-Revision: ${SOURCE_REVISION}
EOF

(
	cd "$OUTPUT_DIR"
	set -- ./*.apk packages.adb build-info.txt feed-index.json \
		package-metadata.json installed-files.txt solver-plan.txt \
		verification-summary.txt
	[ ! -f awg-openwrt3.pem ] || set -- "$@" awg-openwrt3.pem
	sha256sum "$@" > SHA256SUMS
)

printf '%s\n' "Packages and ${AWG3_FEED_SIGNING_STATUS} feed written to ${OUTPUT_DIR}"
