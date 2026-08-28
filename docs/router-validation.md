# План проверки на Cudy TR3000 v1

Этот документ отделяет разработку пакета от действий на production router.
Каждый mutation gate требует отдельного подтверждения владельца.

## Gate 0 — локальная проверка

- `make verify`;
- upstream archive hashes;
- clean patch dry-run;
- build официальным SDK;
- наличие всех APK, `packages.adb`, public key и `SHA256SUMS`;
- secret scan artifacts и Actions logs.
- регрессионные fixture-тесты installer rollback, init lifecycle, LuCI RPC и
  граничных значений `Jc/Jmin/Jmax`.

Результат: **GO** только при полностью зелёном CI.

## Gate 1 — read-only router audit

Запустить `scripts/router-preflight.sh` без установки. Зафиксировать:

- `DISTRIB_RELEASE=25.12.5`;
- `DISTRIB_ARCH=aarch64_cortex-a53`;
- `board_name=cudy,tr3000-v1` (display model — только дополнительный сигнал);
- фактическую kernel version;
- свободное место;
- installed AWG2/WireGuard packages;
- владельцев `/usr/bin/awg` и `/usr/bin/awg-quick`;
- network/firewall baseline и доступность управления.

Если kernel остаётся 6.6.x при заявленном OpenWrt 25.12.5, остановиться и
определить происхождение firmware.

## Gate 2 — package-only install

После подтверждения:

1. backup feed/key и package list;
2. установить public key и feed;
3. `apk add amneziawg3`;
4. проверить installed files и package ownership;
5. убедиться, что не появился новый interface/process/route/firewall rule;
6. убедиться, что WireGuard/AWG2 продолжают работать.

Если установлен `amneziawg-go` или `amneziawg-tools`, APK solver должен
отклонить установку до transaction из-за `!amneziawg-go` либо
`!amneziawg-tools`. Это ожидаемый stop condition. Не использовать `--force`,
`--force-overwrite` и не удалять AWG2 в рамках этого gate.

На этом gate UCI network не редактируется. Installer обязан завершиться
сообщением, что работающий netifd ещё не обнаружил новый protocol handler;
`ifup amneziawg3` пока не выполняется.

## Gate 2b — netifd protocol discovery

Это отдельная network-mutation операция и отдельное подтверждение владельца.
Выбрать одно:

- контролируемый `/etc/init.d/network restart` с локальным/резервным доступом;
- плановый reboot с теми же условиями rollback.

`ubus call network reload`, перезапуск `rpcd` и очистка LuCI cache не заменяют
этот gate. До restart/reboot не должно быть конфигурации с автоматическим
запуском; package hooks и installer не выполняют restart сами.

## Gate 3 — disabled configuration

Создать UCI interface с `option auto '0'`, но не поднимать его. Сохранить:

- `/etc/config/network`;
- `ip rule`, `ip route show table all`;
- `nft list ruleset`;
- remote management path.

Проверить `uci changes`, LuCI rendering и redaction. После согласованного
network restart/reboot доказать, что interface не поднялся автоматически.
Не публиковать profile.

## Gate 4 — split-route handshake

Сначала разрешить только адрес/подсеть, не перехватывающую default route:

- `route_allowed_ips=0` либо узкий AllowedIPs;
- поднять интерфейс;
- проверить `ubus`, process ownership и `awg3 show`;
- дождаться свежего handshake;
- проверить, что management и обычный internet не изменились;
- остановить интерфейс и подтвердить clean teardown.

## Gate 5 — controlled full tunnel

Только после отдельного подтверждения:

- обеспечить out-of-band или локальный rollback;
- добавить endpoint host dependency;
- включить routes для `0.0.0.0/0`/`::/0`;
- проверить DNS, MTU, routing и firewall;
- измерить доступность;
- выполнить rollback drill.

## Gate 6 — lifecycle

- reboot с configured interface;
- `restart` и `status` init facade;
- точечный `apk upgrade` на увеличенный `PKG_RELEASE`;
- после текущего upgrade без изменения schema — отдельно согласованный
  `ifdown`/`ifup` только AWG3 interface; проверить новый process/runtime;
- для release с изменённой handler metadata/schema — отдельно согласованный
  network restart/reboot; простой reload metadata не обновляет;
- downgrade/rollback test;
- uninstall aliases и основной package set одной транзакцией, без удаления
  UCI; повторный uninstall должен быть no-op;
- повторная установка.

## Обязательные стоп-условия

- неизвестный владелец link/socket/process;
- пропала remote management connectivity;
- изменился существующий AWG2/WireGuard;
- package manager предлагает удалить или заменить несвязанные пакеты;
- kernel/release/architecture не совпадают;
- secret оказался в log или artifact;
- firewall/route diff выходит за согласованный scope.
