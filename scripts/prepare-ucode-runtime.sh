#!/bin/sh
set -eu

UCODE_COMMIT=85922056ef7abeace3cca3ab28bc1ac2d88e31b1
UCODE_ARCHIVE_SHA256=54dda1e8a2757710c285659e42336f5054f1825f20d01a4016245bbf877f6da7

DESTINATION="${1:-}"
[ -n "$DESTINATION" ] || {
	echo "usage: $0 ABSOLUTE_DESTINATION" >&2
	exit 2
}
case "$DESTINATION" in
	/*) ;;
	*)
		echo "ucode destination must be an absolute path" >&2
		exit 2
		;;
esac
[ ! -e "$DESTINATION" ] || {
	echo "ucode destination already exists: $DESTINATION" >&2
	exit 1
}

ARCHIVE="${DESTINATION}.tar.gz"
SOURCE_DIR="${DESTINATION}/source"
BUILD_DIR="${DESTINATION}/build"
BIN_DIR="${DESTINATION}/bin"

mkdir -p "$SOURCE_DIR" "$BUILD_DIR" "$BIN_DIR"
curl -fsSL \
	"https://codeload.github.com/jow-/ucode/tar.gz/${UCODE_COMMIT}" \
	-o "$ARCHIVE"
printf '%s  %s\n' "$UCODE_ARCHIVE_SHA256" "$ARCHIVE" | sha256sum -c -
tar -xzf "$ARCHIVE" -C "$SOURCE_DIR" --strip-components=1

cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
	-DCOMPILE_SUPPORT=ON \
	-DDEBUG_SUPPORT=OFF \
	-DFS_SUPPORT=ON \
	-DIO_SUPPORT=OFF \
	-DMATH_SUPPORT=OFF \
	-DUBUS_SUPPORT=OFF \
	-DUCI_SUPPORT=OFF \
	-DRTNL_SUPPORT=OFF \
	-DNL80211_SUPPORT=OFF \
	-DRESOLV_SUPPORT=OFF \
	-DSTRUCT_SUPPORT=OFF \
	-DULOOP_SUPPORT=OFF \
	-DLOG_SUPPORT=OFF \
	-DSOCKET_SUPPORT=OFF \
	-DZLIB_SUPPORT=OFF \
	-DDIGEST_SUPPORT=OFF
cmake --build "$BUILD_DIR" --target ucode fs_lib --parallel 2

cat > "${BIN_DIR}/ucode" <<'WRAPPER'
#!/bin/sh
UCODE_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
exec "${UCODE_ROOT}/build/ucode" -L "${UCODE_ROOT}/build/*.so" "$@"
WRAPPER
chmod 0755 "${BIN_DIR}/ucode"

printf 'Prepared OpenWrt 25.12.5 ucode commit %s\n' "$UCODE_COMMIT"
