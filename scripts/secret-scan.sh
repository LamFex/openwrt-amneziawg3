#!/bin/sh
set -eu

REPOSITORY_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$REPOSITORY_ROOT"

command -v rg >/dev/null 2>&1 || {
	echo "ripgrep is required for the secret scan." >&2
	exit 1
}

if command -v gitleaks >/dev/null 2>&1; then
	gitleaks detect --source . --no-git --redact --exit-code 1
elif [ "${AWG3_REQUIRE_GITLEAKS:-0}" = 1 ]; then
	echo "gitleaks is required but was not found." >&2
	exit 1
else
	echo "gitleaks not found; running repository policy scan only." >&2
fi

if rg -l -uuu --hidden --glob '!.git/**' \
	-e '217\.144\.185\.82|217\.144\.185\.' \
	-e '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----' \
	-e 'github_pat_[A-Za-z0-9_]+' \
	-e 'gh[pousr]_[A-Za-z0-9]{20,}' \
	-e 'AKIA[0-9A-Z]{16}' \
	-e 'ssh-(rsa|ed25519) [A-Za-z0-9+/]{40,}' \
	. >/dev/null; then
	echo "A prohibited credential pattern or production IP was found." >&2
	exit 1
fi

FORBIDDEN_FILES="$(find . -path './.git' -prune -o -type f \( \
	-name '*.pem' -o -name '*.key' -o -name '*.mobileconfig' -o \
	-name '*.vpn' -o -name '*.awg' -o -name '*.profile' -o \
	-name '.env*' -o -name '.DS_Store' -o -name '*.apk' -o \
	-name '*.ipk' -o -name '*.bak' -o -name '*.backup' -o \
	-name '*.orig' -o -name '*.rej' \
	\) -print)"
[ -z "$FORBIDDEN_FILES" ] || {
	echo "Forbidden local, secret, or generated files were found:" >&2
	printf '%s\n' "$FORBIDDEN_FILES" >&2
	exit 1
}

echo "Repository secret scan passed."
