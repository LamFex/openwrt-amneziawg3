## Scope

Опишите изменение и почему оно остаётся в scope первого релиза.

## Проверки

- [ ] `make verify`
- [ ] `./scripts/verify-upstream.sh`
- [ ] `./scripts/verify-patches.sh`
- [ ] Pinned OpenWrt SDK build, если менялся код пакетов
- [ ] Нет private keys, profiles, credentials, signing keys или production endpoints
- [ ] Нет неявных изменений default route, firewall, AWG2 или WireGuard
- [ ] Русская пользовательская документация обновлена вместе с поведением

## Device evidence

Оставьте пустым, если device testing не был отдельно разрешён и выполнен по
`docs/router-validation.md`. Прикладывайте только redacted evidence.
