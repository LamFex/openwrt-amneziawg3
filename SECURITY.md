# Security Policy

## Поддерживаемые версии

Security fixes выпускаются только для последнего release первого
поддерживаемого ряда OpenWrt 25.12.5 / `aarch64_cortex-a53`.

## Сообщение об уязвимости

Используйте **GitHub Security Advisories → Report a vulnerability**. Не
публикуйте issue с private keys, client profiles, router backups, публичным IP
в связке с credentials или Actions signing key.

В сообщении достаточно:

- версии APK и OpenWrt;
- модели устройства;
- минимального воспроизведения с синтетическими ключами;
- redacted log;
- ожидаемого security impact.

## Границы доверия

- APK feed доверяется только после установки проверенного публичного ключа.
- Release private signing key хранится только в GitHub Actions secret.
- netifd владеет foreground-процессом `amneziawg-go`.
- UCI содержит client secrets; `/etc/config/network` должен оставаться
  доступным только root.
- `awg-quick3` является явно запускаемым compatibility tool и может менять
  маршруты/firewall.
- APK solver запрещает совместную установку конфликтующих AWG2/AWG3 runtime и
  tools packages через `!amneziawg-go` и `!amneziawg-tools`; `pre-install`
  hook является только дополнительной диагностикой.

См. [security-model.md](docs/security-model.md).
