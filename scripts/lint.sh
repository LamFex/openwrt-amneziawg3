#!/bin/sh
set -eu

REPOSITORY_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$REPOSITORY_ROOT"

if ! command -v rg >/dev/null 2>&1; then
	echo "ripgrep is required for repository security checks." >&2
	exit 1
fi

set -- \
	amneziawg-go/files/amneziawg3.init \
	amneziawg-tools/files/amneziawg3-key-helper \
	amneziawg-tools/files/amneziawg3.sh \
	amneziawg-tools/files/amneziawg3_watchdog \
	amneziawg-tools/files/awg-quick3 \
	amneziawg-tools/files/awg3 \
	scripts/build-sdk.sh \
	scripts/install.sh.in \
	scripts/lint.sh \
	scripts/router-preflight.sh \
	scripts/prepare-ucode-runtime.sh \
	scripts/secret-scan.sh \
	scripts/verify-apk-feed.sh \
	scripts/verify-patches.sh \
	scripts/verify-upstream.sh \
	tests/run.sh \
	tests/test-installer.sh \
	tests/test-j-validation.sh \
	tests/test-key-helper.sh \
	tests/test-lifecycle.sh \
	tests/test-repository-policy.sh \
	tests/test-ucode-runtime.sh

for file do
	sh -n "$file"
done

if command -v shellcheck >/dev/null 2>&1; then
	shellcheck -x "$@"
fi

if command -v node >/dev/null 2>&1; then
	node -e "
		const fs = require('fs');
		new Function(fs.readFileSync(
			'luci-proto-amneziawg3/htdocs/luci-static/resources/protocol/amneziawg3.js',
			'utf8'
		));
	"
fi

if command -v ucode >/dev/null 2>&1; then
	ucode -c -o /dev/null \
		luci-proto-amneziawg3/root/usr/share/rpcd/ucode/luci.amneziawg3 \
		>/dev/null
fi

if command -v jq >/dev/null 2>&1; then
	jq empty luci-proto-amneziawg3/root/usr/share/rpcd/acl.d/luci-amneziawg3.json
fi

if command -v msgfmt >/dev/null 2>&1; then
	msgfmt --check --check-format -o /dev/null \
		luci-proto-amneziawg3/po/ru/amneziawg3.po
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	git diff --check
fi

if rg -n --hidden \
	--glob '!.git/**' \
	--glob '!tests/fixtures/expected-awg3.conf' \
	"(?i)(privatekey|presharedkey|headerprotectionkey)[[:space:]]*=[[:space:]]*[\"']?[A-Za-z0-9+/]{43}=|option[[:space:]]+(private_key|preshared_key|header_protection_key)[[:space:]]+[\"']?[A-Za-z0-9+/]{43}=|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----" \
	. >/dev/null; then
	echo "Potential private key material found in repository sources." >&2
	exit 1
fi

if rg -n --hidden \
	--glob '!.git/**' \
	'(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})' \
	. >/dev/null; then
	echo "Potential access credential found in repository sources." >&2
	exit 1
fi

if rg -n 'AdvancedSecurity=' \
	amneziawg-tools/files \
	luci-proto-amneziawg3/htdocs >/dev/null; then
	echo "AdvancedSecurity must not be emitted to the AWG3 userspace UAPI." >&2
	exit 1
fi

echo "Static checks passed."
