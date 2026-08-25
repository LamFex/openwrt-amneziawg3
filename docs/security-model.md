# Security model

## Защищаемые данные

- client private key;
- preshared key;
- header protection key;
- полный client profile;
- APK signing private key;
- router backup и management credentials.

## Меры

- runtime config создаётся только как pipe в `awg3 syncconf`;
- LuCI RPC вызывает фиксированный `/usr/libexec` helper через core
  `system(argv)`, без shell evaluation, и получает результат через анонимный
  pipe;
- private key поступает в `awg3 pubkey` через stdin, а не argv; key RPC не
  пишет ключи в файл и не логирует их;
- public key сохранённого interface вычисляется helper после чтения private
  key из UCI по проверенному имени section, поэтому LuCI не отправляет private
  key как RPC parameter;
- router preflight редактирует чувствительные UCI options и production endpoint;
- Git игнорирует profiles, PEM и key files;
- release job требует отдельный base64 Actions secret;
- public feed содержит только APK, signed index, public key и checksums.

UCI остаётся persistent secret store OpenWrt. Права
`/etc/config/network` и backup-файлов должны быть root-only.

## Supply chain

Upstream sources закреплены tag, version и SHA-256. OpenWrt SDK закреплён
точным filename и SHA-256. GitHub Actions закреплены immutable commit SHA.

Обычный CI создаёт unsigned artifact с пометкой `test-only` и вообще не
получает signing secret. Такой artifact нельзя подключать как production feed.
Только trusted tag workflow может получить dedicated signing secret; release
workflow fail-closed при его отсутствии.

Для APK в OpenWrt 25.12 используются ожидаемые build-system filenames
`private-key.pem` и `public-key.pem`; release job проверяет, что private key —
EC P-256, а в artifacts копируется только public key.

## Process authority

Только netifd создаёт foreground daemon через `proto_run_command` и завершает
его через `proto_kill_command`. PID files и поиск/kill по имени не
используются.

При pre-existing link или UAPI socket helper не присваивает их себе и не
удаляет.

## Junk packet allocation

Userspace runtime выделяет junk packet buffers на основе `Jc`, `Jmin` и
`Jmax`, поэтому формальная ширина UAPI `uint16` не является безопасной
политикой пакета. Backend и LuCI принимают только полный набор с пределами
`Jc <= 128`, `Jmax <= 1280`, строгим `Jmin < Jmax` и бюджетом
`Jc * Jmax <= 163840`. Проверка выполняется до запуска daemon. Детали и ссылки
на закреплённый upstream: [junk-parameter-safety.md](junk-parameter-safety.md).

## Installer rollback

One-command installer предназначен только для первой установки. До mutation
он сохраняет полный список имён/версий пакетов, world, feed, public key и init
facade. При ошибке он временно защищает все ранее установленные пакеты в world,
удаляет только новые package names, повторяет удаление broken-script package с
`--no-scripts`, восстанавливает прежние версии и сравнивает итог с snapshot.

Rollback может остаться неполным, если репозиторий больше не предоставляет
точную прежнюю версию или сам APK/database повреждён. В этом случае installer
явно печатает `ROLLBACK INCOMPLETE` и путь к root-only snapshot; он не заявляет
успех и не изменяет сеть.

Имена и точные версии snapshot читаются через machine-oriented APK 3 query
fields (`--summarize name`/`--summarize package`), а не через нестабильный для
парсинга human-readable вывод `apk info`.

Отдельное ограничение APK 3.0.5: nonzero pre-deinstall script не запрещает
удаление package files. Поэтому uninstall должен подтвердить остановку всех
AWG3 interfaces отдельной командой до `apk del`; package hook является
defense-in-depth и диагностическим сигналом.

## Routes и firewall

Основной netifd path не вызывает `awg-quick3`. Routes создаются только из
AllowedIPs peer с explicit `route_allowed_ips=1`. Default — 0.

Compatibility command `awg-quick3` может менять policy routing и firewall
только при явном запуске пользователя. Он не запускается package hooks,
init script или LuCI автоматически.

## Не покрывается

- компрометация root на роутере;
- безопасность существующего VPS/server container;
- неподдерживаемая firmware или архитектура;
- ручное выполнение произвольных hooks в awg-quick profile;
- защита secrets, скопированных пользователем в issue/log.
