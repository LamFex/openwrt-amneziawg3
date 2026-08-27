#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

REPOSITORY_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$REPOSITORY_ROOT"

package_makefiles=(
	amneziawg-go/Makefile
	amneziawg-tools/Makefile
	amneziawg-tools-aliases/Makefile
	amneziawg3/Makefile
	luci-proto-amneziawg3/Makefile
)

for makefile in "${package_makefiles[@]}"; do
	release="$(sed -n 's/^PKG_RELEASE:=//p' "$makefile")"
	[[ "$release" == 2 ]] || {
		echo "$makefile has incoherent PKG_RELEASE=$release" >&2
		exit 1
	}
done

if rg -n '^PKG_CPE_ID:=' "${package_makefiles[@]}" >/dev/null; then
	echo 'An unverified CPE identifier is present.' >&2
	exit 1
fi
grep -Fxq 'PKG_MAINTAINER:=AWG OpenWrt3 contributors' \
	luci-proto-amneziawg3/Makefile
grep -Fxq 'LUCI_MAINTAINER:=$(PKG_MAINTAINER)' \
	luci-proto-amneziawg3/Makefile
grep -Fq 'пока намеренно указывают коллективное имя' CONTRIBUTING.md
grep -Fq 'Name <email>' CONTRIBUTING.md
grep -Fq '**UNOFFICIAL / НЕОФИЦИАЛЬНЫЙ ПРОЕКТ.**' README.md
if rg -n '217\.144\.185\.82|217\.144\.185\.' \
		--glob '!.git/**' . >/dev/null; then
	echo 'A production endpoint remains in repository sources.' >&2
	exit 1
fi

grep -Fq 'DEPENDS:=@TARGET_mediatek_filogic $(GO_ARCH_DEPENDS) +kmod-tun' \
	amneziawg-go/Makefile
grep -Fq 'CONFLICTS:=amneziawg-go' amneziawg-go/Makefile
grep -Fq 'DEPENDS:=+amneziawg3-go +bash +ip-full +netifd +nftables-json +resolveip' \
	amneziawg-tools/Makefile
grep -Fq 'CONFLICTS:=amneziawg-tools' amneziawg-tools-aliases/Makefile
grep -Fxq 'define Build/Compile' amneziawg-tools-aliases/Makefile
grep -Fxq 'define Build/Configure' amneziawg-tools-aliases/Makefile
grep -Fq '+luci-i18n-amneziawg3-ru' amneziawg3/Makefile
if grep -Fq 'amneziawg3-tools-aliases' amneziawg3/Makefile; then
	echo 'Default meta-package unexpectedly depends on optional aliases.' >&2
	exit 1
fi
grep -Fq 'amneziawg3-key-helper' amneziawg-tools/Makefile
grep -Fq 'define Package/amneziawg3-tools/prerm' amneziawg-tools/Makefile

grep -Fq 'board_name=cudy,tr3000-v1' README.md
grep -Fq '[ "$BOARD_NAME" = "cudy,tr3000-v1" ]' scripts/install.sh.in
grep -Fq "option auto '0'" README.md docs/router-validation.md
grep -Fq 'Gate 2b — netifd protocol discovery' docs/router-validation.md
grep -Fq 'ubus call network reload' docs/architecture.md docs/troubleshooting.md
grep -Fq 'не выполняют restart сами' docs/router-validation.md
grep -Fq 'ifdown <interface>`/`ifup <interface>' docs/architecture.md
grep -Fq 'Для текущего `-r2`' README.md

if rg -n '^[[:space:]]*(/etc/init.d/network|ifup|reboot)([[:space:]]|$)' \
		amneziawg-go/Makefile amneziawg-tools/Makefile \
		luci-proto-amneziawg3/Makefile scripts/install.sh.in >/dev/null; then
	echo 'A package or installer hook performs an automatic network mutation.' >&2
	exit 1
fi

grep -Fq 'Jc × Jmax <= 163840' docs/junk-parameter-safety.md
grep -Fq 'проверяет их до запуска `amneziawg-go`' docs/junk-parameter-safety.md
grep -Fq 'Jc <= 128' docs/security-model.md
grep -Fq 'поступает в `awg3 pubkey` только через stdin' docs/architecture.md

acl=luci-proto-amneziawg3/root/usr/share/rpcd/acl.d/luci-amneziawg3.json
ucode=luci-proto-amneziawg3/root/usr/share/rpcd/ucode/luci.amneziawg3
js=luci-proto-amneziawg3/htdocs/luci-static/resources/protocol/amneziawg3.js
for method in generateKeyPair deriveStoredPublicKey generatePresharedKey; do
	grep -Fq "$method" "$acl"
	grep -Fq "$method" "$ucode"
	grep -Fq "$method" "$js"
done

go_version="$(sed -n 's/^PKG_VERSION:=//p' amneziawg-go/Makefile)"
tools_version="$(sed -n 's/^PKG_VERSION:=//p' amneziawg-tools/Makefile)"
[[ "$go_version" == 3.1.* && "$tools_version" == 3.1.* ]]
grep -Fq "AWG_GO_VERSION=${go_version}" scripts/build-sdk.sh
grep -Fq "AWG_TOOLS_VERSION=${tools_version}" scripts/build-sdk.sh
grep -Fq 'Feed-Signing: ${AWG3_FEED_SIGNING_STATUS}' scripts/build-sdk.sh
grep -Fq 'PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)' \
	luci-proto-amneziawg3/Makefile
for package_makefile in amneziawg3/Makefile \
	amneziawg-tools-aliases/Makefile; do
	package_name="$(sed -n 's/^PKG_NAME:=//p' "$package_makefile")"
	sed -n "/^define Package\/${package_name}$/,/^endef$/p" \
		"$package_makefile" | grep -Fq '  PKGARCH:=all'
done
grep -Fq 'Package-Count: 6' scripts/verify-apk-feed.sh
[[ "$(rg -c '^validate_metadata .* noarch ' scripts/verify-apk-feed.sh)" == 4 ]]
[[ "$(rg -c '^validate_metadata .* aarch64_cortex-a53 ' \
	scripts/verify-apk-feed.sh)" == 2 ]]
if rg -n '^validate_metadata .* all ' scripts/verify-apk-feed.sh >/dev/null; then
	echo 'APK v3 metadata must use noarch for PKGARCH:=all packages.' >&2
	exit 1
fi
grep -Fq 'package/feeds/awg3/amneziawg-tools/compile' scripts/build-sdk.sh
grep -Fq 'package/feeds/awg3/amneziawg-tools-aliases/compile' scripts/build-sdk.sh
if rg -n 'package/feeds/awg3/amneziawg3-tools(-aliases)?/compile' \
		scripts/build-sdk.sh >/dev/null; then
	echo 'An SDK target uses a binary package name instead of its feed directory.' >&2
	exit 1
fi
grep -Fq 'umask 022' scripts/build-sdk.sh
grep -Fq 'chmod 0700 "$BUILD_ROOT"' scripts/build-sdk.sh
grep -Fq 'umask 077' scripts/build-sdk.sh
grep -Fq 'chmod 0600 "$APK_PRIVATE_KEY"' scripts/build-sdk.sh
grep -Fq 'UCODE_COMMIT=85922056ef7abeace3cca3ab28bc1ac2d88e31b1' \
	scripts/prepare-ucode-runtime.sh
grep -Fq 'ucode runtime is mandatory in CI' tests/test-ucode-runtime.sh
grep -Fq 'APK metadata, files, index, and solver checks passed.' \
	scripts/verify-apk-feed.sh
if rg -n '"\$APK_TOOL".* manifest ' scripts/verify-apk-feed.sh >/dev/null; then
	echo 'The feed verifier must not require an initialized apk database.' >&2
	exit 1
fi
grep -Fq 'scripts/verify-apk-feed.sh' scripts/lint.sh
grep -Fq '*bash) bash -n' scripts/lint.sh

echo 'Repository policy tests passed.'
