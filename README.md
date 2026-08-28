# AWG OpenWrt3

> [!WARNING]
> **UNOFFICIAL / НЕОФИЦИАЛЬНЫЙ ПРОЕКТ.** Проект не аффилирован с Amnezia,
> OpenWrt Project или их разработчиками и не является официальным пакетом
> AmneziaWG либо OpenWrt.

Пакеты AmneziaWG 3.1 для OpenWrt с интеграцией в `apk`, netifd, UCI и LuCI.
Цель проекта — дать AmneziaWG 3.1 тот же понятный жизненный цикл, что и у
штатного WireGuard: установка из подписанного feed, настройка интерфейса через
LuCI, запуск через netifd и точечное обновление пакетов.

> [!IMPORTANT]
> Проект находится на стадии первого release candidate. CI проверяет исходники
> и собирает artifacts закреплённым официальным SDK; каждый commit обязан
> пройти эти gates. Испытание на реальном роутере ещё не выполнено, поэтому
> пакет нельзя считать production-ready до прохождения
> [router validation](docs/router-validation.md).

## Поддерживаемая платформа

| Компонент | Первый релиз |
|---|---|
| OpenWrt | **25.12.5** |
| Target | `mediatek/filogic` |
| Package architecture | `aarch64_cortex-a53` |
| Устройство | **Cudy TR3000 v1** |
| Реализация | `amneziawg-go` userspace через TUN |
| AmneziaWG Go | `3.1.20260814` |
| AmneziaWG tools | `3.1.20260812` |

Другие версии OpenWrt, архитектуры и устройства намеренно не поддерживаются
первым релизом. Официальный образ OpenWrt 25.12.5 для Filogic использует ядро
6.12.x; если роутер сообщает 6.6.x, это признак другого или изменённого образа
и обязательная причина остановить установку до аудита.

Существующий сервер AmneziaWG 3.1, контейнеры VPS и серверный UDP-порт проект
не меняет. Пакет содержит только клиентскую поддержку OpenWrt.

## Архитектура пакетов

| Пакет | Назначение |
|---|---|
| `amneziawg3-go` | `/usr/bin/amneziawg-go` и init-фасад |
| `amneziawg3-tools` | `awg3`, `awg-quick3`, netifd protocol helper |
| `luci-proto-amneziawg3` | протокол **AmneziaWG 3.1** в LuCI |
| `luci-i18n-amneziawg3-ru` | русская локализация LuCI protocol plugin |
| `amneziawg3` | безопасный meta-package для обычной установки |
| `amneziawg3-tools-aliases` | опциональные `/usr/bin/awg` и `/usr/bin/awg-quick` |

Стандартные имена `awg` и `awg-quick` вынесены в отдельный пакет. Поэтому
обычный `apk add amneziawg3` не перезаписывает команды существующего AWG2.
Runtime package называется `amneziawg3-go` и конфликтует с legacy package
`amneziawg-go`. Пакеты `amneziawg3-tools` и
`amneziawg3-tools-aliases` намеренно конфликтуют с legacy
`amneziawg-tools`. OpenWrt 25.12 APK metadata содержит отрицательные
зависимости `!amneziawg-go` и `!amneziawg-tools`, поэтому solver обязан
остановить транзакцию до удаления или замены AWG2. Исходные `CONFLICTS`
сохранены для декларативной и IPK-совместимости.

Package `pre-install` проверяет чужой init facade только как дополнительную
диагностику. Он не считается security boundary: запрет совместной установки
доказывается по metadata реально собранных APK и disposable solver-тестами.

netifd является единственным владельцем foreground-процесса
`amneziawg-go -f <interface>`. Init script не управляет PID самостоятельно:
он вызывает `ifup`/`ifdown` для UCI-интерфейсов. Подробности:
[architecture.md](docs/architecture.md).

## До установки

На роутере выполните только read-only preflight:

```sh
sh ./scripts/router-preflight.sh
```

Сохраните вывод без ключей и проверьте:

- точную версию OpenWrt, архитектуру и модель;
- свободное место на overlay;
- владельцев существующих `awg`, `awg-quick` и WireGuard-пакетов;
- существующие AWG2/WireGuard-интерфейсы и процессы;
- отсутствие неожиданного интерфейса или UAPI socket с выбранным именем.

Preflight редактирует вывод UCI и скрывает private, preshared и header
protection keys, а также production endpoint. Он ничего не устанавливает и не
меняет.

## Установка из release feed

До публикации GitHub Pages замените `<OWNER>` и `<REPOSITORY>` реальными
значениями. Сначала скачайте и просмотрите installer:

```sh
wget -O /tmp/install-awg3.sh \
  https://<OWNER>.github.io/<REPOSITORY>/install.sh
less /tmp/install-awg3.sh
```

После явного подтверждения установка выполняется одной командой:

```sh
AWG3_INSTALL_CONFIRM=YES sh /tmp/install-awg3.sh
```

Installer:

1. требует OpenWrt 25.12.5, `aarch64_cortex-a53` и точный
   `board_name=cudy,tr3000-v1`;
2. сохраняет package names/versions, APK world, init facade, feed и ключ в
   приватный `/root/awg3-install-backup-*`;
3. проверяет SHA-256 публичного ключа;
4. добавляет подписанный `packages.adb`;
5. устанавливает `amneziawg3`;
6. ставит standard aliases только если `awg`/`awg-quick` свободны;
7. при ошибке удаляет только новые packages этой попытки, восстанавливает
   прежние versions/world/feed/key и fail-closed сообщает о неполном rollback;
8. **не** создаёт интерфейс, маршрут или firewall rule.

Installer предназначен только для первой установки. Если любой пакет проекта
уже установлен, он останавливается до mutation и направляет пользователя к
точечному `apk upgrade`.

### Ручное подключение feed

```sh
wget -O /etc/apk/keys/awg-openwrt3.pem \
  https://<OWNER>.github.io/<REPOSITORY>/feed/awg-openwrt3.pem

echo 'https://<OWNER>.github.io/<REPOSITORY>/feed/aarch64_cortex-a53/packages.adb' \
  >> /etc/apk/repositories.d/customfeeds.list

apk update
apk add amneziawg3
```

Прямая установка допустима только без `--force` и `--force-overwrite`.
AWG3-пакеты намеренно конфликтуют с legacy AWG2 packages там, где совместная
установка могла бы заменить runtime или столкнуться с tool paths. Если solver
сообщил конфликт, остановитесь: не удаляйте и не заменяйте AWG2 автоматически.

Перед ручной установкой самостоятельно сверяйте fingerprint ключа с
`SHA256SUMS` GitHub Release.

## Gate обнаружения netifd protocol

Первая package-only установка заканчивается без рестарта сети. Уже запущенный
`netifd` не перечитывает новый файл
`/lib/netifd/proto/amneziawg3.sh`, поэтому сразу выполнять `ifup awg3` нельзя.
`/etc/init.d/network reload` и restart `rpcd` этого не исправляют.

После отдельного подтверждения и только при наличии локального/rollback
канала выполните один controlled network mutation:

```sh
# Полностью перезапускает netifd и все network interfaces:
/etc/init.d/network restart

# Альтернатива — запланированный reboot.
```

Installer и package hooks не выполняют этот шаг автоматически. До него AWG3
UCI interface создавать не требуется. После него новый protocol handler будет
доступен, но tunnel по-прежнему не появится сам.

## Настройка через LuCI

После установки:

1. откройте **Network → Interfaces**;
2. выберите **Add new interface**;
3. укажите протокол **AmneziaWG 3.1**;
4. создайте или вставьте client private key;
5. добавьте адрес интерфейса и peer сервера;
6. скопируйте AWG 3.1 параметры точно из клиентского профиля;
7. в common interface settings отключите автозапуск (`option auto '0'`);
8. сохраните изменения без немедленного применения, проверьте diff и rollback;
9. применяйте только в согласованное окно проверки.

`Route allowed IPs` по умолчанию выключен. Это защищает текущий default route
от неожиданной замены при добавлении peer.

## Настройка через UCI

OpenWrt хранит peer отдельной секцией, как официальный WireGuard protocol
helper. Серверный public key и реальные AWG 3.1 параметры берутся из
существующего client profile; их нельзя угадывать.

```uci
config interface 'awg3'
	option proto 'amneziawg3'
	option auto '0'
	option private_key 'CLIENT_PRIVATE_KEY'
	list addresses '10.x.x.x/32'
	option mtu '1420'
	option jc '4'
	option jmin '40'
	option jmax '70'
	option s1 '12'
	option s2 '12'
	option s3 '12'
	option s4 '12'
	option h1 '1000000-2000000'
	option h2 '2000001'
	option header_protection_key 'PROFILE_HEADER_PROTECTION_KEY'
	option rekey_after_time '120-180'
	option random_trailers '1'

config amneziawg3_awg3
	option description 'Debian VPS'
	option public_key 'SERVER_PUBLIC_KEY'
	option endpoint_host '203.0.113.10'
	option endpoint_port '4242'
	list allowed_ips '0.0.0.0/0'
	list allowed_ips '::/0'
	option persistent_keepalive '20-30'
	option route_allowed_ips '0'
```

`Jc`, `Jmin` и `Jmax` задаются только полной тройкой: `Jc=1…128`,
`Jmin=0…1279`, `Jmax=1…1280`, причём `Jmin < Jmax`. Backend проверяет также
worst-case allocation budget до запуска daemon. Обоснование и точная модель:
[junk-parameter-safety.md](docs/junk-parameter-safety.md).

Поля `H1`–`H4`, timing-параметры и `PersistentKeepalive` допускают одно число
или диапазон `min-max`. При `HeaderProtectionKey` значения `S1`–`S4` должны
быть не меньше 12. Поле `AdvancedSecurity` не записывается: AWG 3.1 userspace
UAPI использует protocol version 1 и отвергает этот legacy peer flag.

Перед первым запуском:

```sh
umask 077
uci export network > /root/network-before-awg3.uci
uci changes network
```

Первый контролируемый запуск:

```sh
ifup awg3
ubus call network.interface.awg3 status
awg3 show awg3
```

`option auto '0'` не мешает явному `ifup`, но не позволяет netifd поднять
тестовый интерфейс при reboot/network restart. После завершения validation его
можно отдельно изменить на `1`, предварительно проверив `uci changes network`.

Не включайте `route_allowed_ips=1`, пока handshake и доступность endpoint не
проверены через текущий WAN.

После успешных lifecycle-тестов доступен штатный init-фасад:

```sh
/etc/init.d/amneziawg3 start
/etc/init.d/amneziawg3 stop
/etc/init.d/amneziawg3 restart
/etc/init.d/amneziawg3 enable
/etc/init.d/amneziawg3 status
```

Он делегирует операции netifd и не создаёт второй daemon/process owner.
`enable`/`disable` управляют только запуском самого init-фасада при boot и не
меняют UCI option `auto`. Даже enabled-фасад пропускает каждый AWG3 interface
с `option auto '0'`; явный `ifup awg3` остаётся отдельной ручной операцией.

## Обновление

Feed публикует возрастающие package versions/releases, поэтому поддерживается
обычный APK lifecycle:

```sh
apk update
apk upgrade amneziawg3-go amneziawg3-tools luci-proto-amneziawg3 \
  luci-i18n-amneziawg3-ru amneziawg3
```

Если установлен optional alias package, обновляйте и его:

```sh
apk upgrade amneziawg3-tools-aliases
```

Не запускайте безадресный `apk upgrade` на OpenWrt: официальный OpenWrt
предупреждает, что массовое обновление всех firmware-пакетов может создать
несогласованную систему. Проект гарантирует только точечное обновление своих
пакетов.

Установка и upgrade не вызывают автоматический restart сети или активного
AWG3 interface и не переписывают `/etc/config/network`. После upgrade активный
daemon остаётся прежним процессом. Уже зарегистрированный netifd handler при
следующем lifecycle action запускает обновлённый script по тому же пути.

Для текущего `luci-proto-amneziawg3` `-r2`, где `proto_config` schema не
менялась, выполните отдельный controlled restart только тестируемого AWG3
interface:

```sh
ifdown awg3
ifup awg3
```

Сначала сохраните rollback и убедитесь, что его routes не перехватят management
path. Если release notes будущего обновления сообщают об изменении handler
metadata/schema, потребуется полный controlled `/etc/init.d/network restart`
или reboot: обычный network reload такую metadata не перечитывает. Ни один из
этих шагов package hooks не выполняет автоматически.

## Остановка, rollback и удаление

Быстрый rollback первого запуска:

```sh
ifdown awg3
uci import network < /root/network-before-awg3.uci
uci commit network
/etc/init.d/network reload
```

Перед import убедитесь, что backup относится к текущему роутеру и нужному
моменту. В удалённой сессии безопаснее сначала убрать только
`route_allowed_ips`, выполнить `ifdown awg3` и проверить доступность управления.

Удаление пакетов не удаляет UCI-секции автоматически. Optional aliases
удаляются первыми в той же APK transaction; snippet безопасен, если aliases
не установлены, tools использовался без них или удаление запускается повторно:

```sh
set -e

# Останавливает все UCI interfaces с proto=amneziawg3, пока protocol handler
# ещё установлен. При ошибке package removal не продолжается.
if [ -x /etc/init.d/amneziawg3 ]; then
  /etc/init.d/amneziawg3 stop
fi

packages=
for package in \
  amneziawg3-tools-aliases \
  amneziawg3 \
  luci-i18n-amneziawg3-ru \
  luci-proto-amneziawg3 \
  amneziawg3-tools \
  amneziawg3-go; do
  if apk query --installed --summarize name "$package" 2>/dev/null |
      grep -Fxq "$package"; then
    packages="${packages} ${package}"
  fi
done
[ -z "$packages" ] || apk del $packages
```

`amneziawg3-tools` повторяет этот stop в pre-deinstall hook. Это защита от
обычного прямого `apk del`, но не замена явному шагу выше: APK 3.0.5 помечает
неуспешный pre-deinstall как broken script и возвращает ошибку, однако может
продолжить удаление файлов. Поэтому именно успешный pre-stop до начала APK
transaction является обязательным rollback gate. Hook не удаляет UCI sections
и не затрагивает WireGuard/AWG2.

Feed URL и публичный ключ удаляйте только после сохранения rollback-копии и
проверки, что другие пакеты из этого feed не установлены.

## Диагностика

```sh
/etc/init.d/amneziawg3 status
ubus call network.interface.awg3 status
awg3 show awg3
ip -details link show dev awg3
logread -e amneziawg3
apk info amneziawg3-go amneziawg3-tools luci-proto-amneziawg3 \
  luci-i18n-amneziawg3-ru
```

Отсутствие socket-файла или его наличие само по себе не считается readiness.
Protocol helper ждёт успешного `awg3 show <interface>`. Если до запуска уже
существует интерфейс или `/var/run/amneziawg/<interface>.sock`, helper
останавливается и ничего не удаляет.

См. [troubleshooting.md](docs/troubleshooting.md).

## `awg-quick3`

`awg-quick3` включён как совместимый CLI, но основной способ работы —
UCI/netifd/LuCI. Он всегда запускает userspace AWG3 и не пытается использовать
загруженный AWG2 kernel module.

Короткое имя интерфейса ищется только в
`/etc/amnezia/amneziawg3/<interface>.conf`; каталог legacy AWG2
`/etc/amnezia/amneziawg/` не используется.

Явный `awg-quick3 up` может менять адреса, policy routing и firewall. Параметр
`DNS=` на OpenWrt намеренно отвергается; DNS настраивается через UCI/LuCI.
Пакет никогда не запускает `awg-quick3` автоматически.

`amneziawg3_watchdog` можно отдельно добавить в cron для повторного DNS
resolution неактивных peers с `PersistentKeepalive`. Package hooks не добавляют
cron job автоматически.

## Сборка

На x86_64 Linux:

```sh
./scripts/verify-upstream.sh
./scripts/verify-patches.sh
make verify
./scripts/build-sdk.sh
```

Сборка загружает строго OpenWrt SDK 25.12.5 для `mediatek/filogic` и проверяет
его SHA-256. Обычный CI создаёт unsigned test feed без постоянного signing key;
результат находится в `dist/`. Только trusted tag workflow формирует
подписанный release feed.

Release workflow требует GitHub Actions secret
`AWG3_APK_PRIVATE_KEY_B64`: base64-представление PEM EC private key. Private
key никогда не должен попадать в Git, Actions artifacts или release.
Подробности: [release.md](docs/release.md).

## Состояние проверок

- [x] pinned upstream tags и tarball SHA-256;
- [x] локальная ARM64 cross-compilation `amneziawg-go`;
- [x] shell/JavaScript/ucode/JSON/YAML static parsing;
- [x] fixture-тест генерируемого AWG3.1 config stream;
- [x] collision-safe package layout для AWG2;
- [ ] полный build официальным OpenWrt SDK в GitHub Actions;
- [ ] установка APK на Cudy TR3000 v1;
- [ ] handshake без изменения default route;
- [ ] controlled full-tunnel test;
- [ ] upgrade и rollback на реальном устройстве.

До закрытия последних пунктов GitHub Release должен иметь пометку prerelease.

## Upstream и лицензии

- [amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go)
- [amneziawg-tools](https://github.com/amnezia-vpn/amneziawg-tools)
- [OpenWrt](https://github.com/openwrt/openwrt)
- [LuCI](https://github.com/openwrt/luci)
- [awg-openwrt](https://github.com/Slava-Shchipunov/awg-openwrt) — источник
  структурных идей для legacy AWG2 integration

Оригинальный glue code проекта распространяется по MIT license. LuCI и
netifd helper — Apache-2.0. Patch для upstream `amneziawg-tools` и сам
upstream tools остаются GPL-2.0-only, а `amneziawg-go` — под своей upstream
MIT license. Полная атрибуция находится в [NOTICE](NOTICE).
