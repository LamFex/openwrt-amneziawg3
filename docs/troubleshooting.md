# Диагностика

## LuCI не показывает AmneziaWG 3.1

```sh
apk info luci-proto-amneziawg3 luci-i18n-amneziawg3-ru
ls -l /www/luci-static/resources/protocol/amneziawg3.js
ls -l /usr/share/rpcd/ucode/luci.amneziawg3
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache
```

Перезапуск `rpcd` не поднимает и не останавливает tunnel interface.

Если LuCI уже видит пакет, но netifd отвечает `Unknown protocol` или interface
остаётся с `PROTO_NOT_FOUND`, работающий netifd не загрузил новый handler.
`ubus call network reload` и перезапуск `rpcd` недостаточны. Не выполняйте
`ifup`: сначала сохраните rollback и отдельно согласуйте
`/etc/init.d/network restart` либо reboot. Installer и package hooks не делают
этого автоматически.

## Ошибки `Jc` / `Jmin` / `Jmax`

- `JUNK_PARAMETERS_INCOMPLETE` — задана только часть тройки;
- `INVALID_JC` — `Jc` не decimal `1..128`;
- `INVALID_JMIN` — `Jmin` не decimal `0..1279`;
- `INVALID_JMAX` — `Jmax` не decimal `1..1280`;
- `INVALID_JUNK_RANGE` — требуется строгое `Jmin < Jmax`;
- `JUNK_MEMORY_BUDGET_EXCEEDED` — превышен бюджет
  `Jc * Jmax <= 163840`.

Backend отклоняет эти значения до запуска `amneziawg-go`, поэтому не нужно
удалять link/socket или чистить routes. Исправьте UCI/LuCI configuration и
повторите явный `ifup`.

## `USERSPACE_NOT_READY`

```sh
logread -e amneziawg3
ps w | grep '[a]mneziawg-go'
ls -la /var/run/amneziawg
ip link show
```

Если socket уже существовал до запуска, helper намеренно его не удаляет.
Определите владельца процесса. Удалять socket можно только после доказательства,
что процесс отсутствует и socket действительно stale.

## `INTERFACE_ALREADY_EXISTS`

```sh
ip -details link show dev awg3
ps w | grep '[a]mneziawg'
apk info --who-owns /usr/bin/awg 2>/dev/null
```

Не удаляйте interface, пока не выяснено, относится ли он к AWG2, WireGuard,
другому netifd interface или ручному process.

## `CONFIGURATION_FAILED`

Чаще всего причины:

- ошибочный Base64 key;
- отсутствующий public key enabled peer;
- несовпадающие AWG 3.1 параметры;
- `S1`–`S4` меньше 12 при HeaderProtectionKey;
- некорректный range;
- неразрешимый endpoint hostname.

Сначала остановите interface и проверьте UCI без вывода private key:

```sh
uci -q show network.awg3 |
  sed -E "s/(private_key|header_protection_key)='[^']*'/\1='<redacted>'/"
```

## Handshake отсутствует

```sh
awg3 show awg3
ip route get 203.0.113.10
logread -e amneziawg3
```

Проверьте server public key, endpoint port 4242, client address,
PersistentKeepalive и все AWG 3.1 параметры. Сервер не изменяйте в рамках
клиентской диагностики.

## После full-tunnel пропал интернет

В локальной консоли или согласованном rollback channel:

```sh
ifdown awg3
```

Затем проверьте `route_allowed_ips`, endpoint host route, DNS и MTU. Не
выполняйте reboot, массовый `apk upgrade` или очистку firewall как способ
диагностики.

## Проверка package/feed

```sh
apk update
apk policy amneziawg3
apk info -L amneziawg3-tools
sha256sum /etc/apk/keys/awg-openwrt3.pem
```

Fingerprint должен совпадать с публичным ключом соответствующего GitHub
Release.
