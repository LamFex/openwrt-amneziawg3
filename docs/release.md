# Выпуск signed APK feed

## 1. Release key

Создайте отдельный EC P-256 key на доверенной offline/secured машине:

```sh
umask 077
openssl ecparam -name prime256v1 -genkey -noout -out awg-openwrt3-private.pem
openssl ec -in awg-openwrt3-private.pem -pubout -out awg-openwrt3.pem
base64 < awg-openwrt3-private.pem | tr -d '\n'
```

Последнюю строку сохраните как GitHub Actions repository secret
`AWG3_APK_PRIVATE_KEY_B64`. Private PEM и base64 value не добавляйте в
repository, issue, artifact или release.

Public key fingerprint публикуется в release notes и вне GitHub по второму
каналу.

## 2. Pre-release gates

```sh
make verify
./scripts/verify-upstream.sh
./scripts/verify-patches.sh
```

Затем дождитесь зелёного workflow **Build OpenWrt APKs** и проверьте artifact:

- шесть expected APK;
- unsigned test `packages.adb`;
- `SHA256SUMS`;
- `build-info.txt`;
- `ci-artifact-status.txt` с `verified-ci-only` для зелёного unsigned build;
- `package-identity.json` с name/version/arch/Depends/Provides/Replaces;
- package metadata и отсутствие secrets;
- `negative-dependencies.json` с APK-native AWG2 conflicts;
- `apk-lifecycle-report.txt` с forward, reverse, partial и upgrade evidence.

Artifact workflow называется
`awg3-ci-only-<commit>-openwrt-25.12.5-mediatek-filogic-aarch64_cortex-a53`.
Если APK compilation завершилась, но последующий verifier упал, workflow всё
равно сохраняет checksummed evidence с `unverified-ci-only` и sanitized
`verification-run.log`; сам workflow остаётся красным. Такой artifact нужен
только для диагностики и не разрешает tag, feed, installer или release.

Public key появляется только в trusted tag build, который требует dedicated
Actions secret. Обычный CI этот secret не получает и private key не создаёт.

## 3. Versioning

- upstream version находится в `PKG_VERSION`;
- OpenWrt-specific rebuild увеличивает `PKG_RELEASE`;
- repository release использует semver tag, например `v0.1.0-rc.1`;
- release остаётся prerelease до device validation.

Не перемещайте опубликованный tag и не переиспользуйте package
version-release с другим содержимым.

## 4. Tag

Commit, push и создание tag выполняются только после отдельного review и
явного подтверждения maintainer. Tag запускает:

1. SDK build;
2. signing APK repository index `packages.adb`;
3. GitHub Release;
4. GitHub Pages feed;
5. rendering installer с feed URL и public-key SHA-256.

GitHub repository Settings → Pages должен использовать **GitHub Actions** как
source.

## 5. После публикации

- скачать release archive и сверить `SHA256SUMS`;
- проверить signature/index на clean OpenWrt 25.12.5 lab device;
- выполнить package-only Gate 2;
- затем router validation Gates 3–6;
- только после evidence снять prerelease.

## 6. Key rotation

При подозрении на компрометацию:

1. остановить release workflow;
2. отозвать secret;
3. не удалять старые releases без advisory;
4. создать новый key и отдельный trust migration release;
5. опубликовать fingerprints обоих ключей и инструкции удаления старого.
