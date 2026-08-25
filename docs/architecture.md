# Архитектура

## Цели

Первый релиз решает одну задачу: безопасно встроить userspace AmneziaWG 3.1 в
штатный lifecycle OpenWrt 25.12.5 на Cudy TR3000 v1.

Основные инварианты:

1. один владелец процесса — netifd;
2. конфигурация формируется в памяти и передаётся `awg3 syncconf` через stdin;
3. package install/upgrade не меняет UCI network;
4. существующие WireGuard и AWG2 остаются независимыми;
5. любые collision или остаточное состояние приводят к fail-closed.

## Компоненты и ownership

```text
LuCI
  │ writes
  ▼
/etc/config/network (UCI)
  │ netifd invokes
  ▼
/lib/netifd/proto/amneziawg3.sh
  ├── proto_run_command → amneziawg-go -f awg3
  ├── readiness → awg3 show awg3
  ├── configuration → awg3 syncconf awg3 /dev/stdin
  └── teardown → proto_kill_command (tracked process only)
```

`/etc/init.d/amneziawg3` — symlink на package-owned фасад совместимости для
`start`, `stop`, `restart`, `enable` и `status`. Он перечисляет UCI interfaces
с `proto=amneziawg3` и вызывает `ifup`/`ifdown`; PID, PID file или собственный
procd instance не создаются. `start` и `restart` пропускают interface с
`option auto '0'`; явный `ifup` остаётся ручным действием. `stop` по-прежнему
останавливает уже поднятый interface независимо от `auto`.

Сам фасад хранится вне `/etc/init.d`, поэтому стандартные OpenWrt package
hooks не запускают и не останавливают tunnel при install/upgrade. Pre-install
и post-install hooks fail-closed при чужом объекте `/etc/init.d/amneziawg3` и
никогда не заменяют его.

Перед deinstall package `amneziawg3-tools` вызывает точный package-owned
фасад `stop`, пока protocol handler ещё находится на месте. Runtime `prerm`
затем удаляет только точный symlink и отключает его boot links; UCI
configuration сохраняется.

APK 3.0.5 не использует ошибку pre-deinstall как transaction veto: он отмечает
broken script, но может продолжить удаление. Поэтому documented uninstall
сначала отдельно и успешно выполняет facade `stop`, и лишь затем запускает
одну APK transaction. Ошибка hook остаётся видимым сигналом residual risk, но
не выдаётся за гарантированный rollback.

## Почему userspace-only

AWG 3.1 реализован в `amneziawg-go` и работает через `kmod-tun`. Пакет не
собирает `kmod-amneziawg`, не вызывает `modprobe amneziawg` и не выбирает
kernel implementation автоматически. Это:

- исключает случайное использование установленного AWG2 kernel module;
- уменьшает зависимость от точного kernel ABI;
- делает процесс видимым и управляемым netifd;
- сохраняет существующий WireGuard/AWG2 stack.

## UCI model

Интерфейс хранится как `config interface` с `proto=amneziawg3`. Peers —
анонимные секции типа `amneziawg3_<interface>`, как у штатного WireGuard
protocol plugin.

`route_allowed_ips` имеет default `0`. Маршруты создаются netifd только по
явному выбору пользователя.

## Readiness и residual state

Socket presence не является readiness. После `proto_run_command` helper до
10 секунд ждёт успешный запрос:

```sh
awg3 show <interface>
```

До запуска проверяются:

- отсутствие pre-existing network link с тем же именем;
- отсутствие pre-existing UAPI socket;
- наличие private key;
- наличие public key у каждого enabled peer.

`Jc`, `Jmin` и `Jmax` проверяются до `proto_run_command`: либо отсутствуют
все три, либо присутствуют все три; `1 <= Jc <= 128`,
`0 <= Jmin < Jmax <= 1280`, `Jc * Jmax <= 163840`. Поэтому ошибочная UCI
конфигурация не успевает создать процесс, link, socket или route. Полное
обоснование лимитов и оценки памяти находится в
[junk-parameter-safety.md](junk-parameter-safety.md).

Helper не удаляет неизвестный link или socket. Stale socket восстанавливается
только отдельной диагностической процедурой после проверки владельца.

## Конфигурационный stream

Секреты не записываются в `/tmp`. Shell helper печатает каждую строку через
`printf '%s\n'`, а stream поступает непосредственно в `awg3 syncconf`.
Значения не передаются через `%b`, поэтому backslash-последовательности не
интерпретируются shell.

LuCI генерирует ключи через фиксированный `/usr/libexec` helper. RPC запускает
его core-функцией `system(argv)` без shell и читает короткий ответ через
унаследованный анонимный pipe. В argv передаётся только номер write-end pipe,
фиксированное действие и, для derive, проверенное имя section. Private key
поступает в `awg3 pubkey` только через stdin и не попадает в argv, log или
временный файл. Сам private key сохранённого interface helper читает из UCI.
Автоматической записи или `uci commit` из netifd helper нет: генерация и
сохранение ключа — явная операция формы LuCI.

`AdvancedSecurity` намеренно отсутствует. В userspace AWG 3.1 peer protocol
уже определяется глобальной protocol version, а tools UAPI отвергает legacy
peer AWG flag.

## CLI namespace

Основные команды:

- `/usr/bin/awg3` → private `/usr/libexec/amneziawg3/awg`;
- `/usr/bin/awg-quick3` → private patched `awg-quick`;
- `/usr/bin/amneziawg-go`.

Опциональный пакет `amneziawg3-tools-aliases` создаёт `awg` и `awg-quick`, но
объявляет conflict с legacy `amneziawg-tools`. Default meta-package от него не
зависит.

Профили явного compatibility command `awg-quick3` находятся в отдельном
каталоге `/etc/amnezia/amneziawg3/`, поэтому одноимённый AWG2 profile не может
быть выбран случайно.

## Upgrade semantics

APK package version следует upstream AmneziaWG version, а `PKG_RELEASE`
увеличивается для OpenWrt-specific fixes. Config files и UCI network не
переписываются. Активный интерфейс не перезапускается post-install hook.

Netifd обнаруживает новые protocol handlers только при старте процесса. После
первого install одного `ubus call network reload` недостаточно: новый handler
становится доступен только после отдельно подтверждённого
`/etc/init.d/network restart` либо reboot. Installer и package hooks этого не
делают автоматически и не вызывают `ifup`.

При upgrade уже зарегистрированный shell handler хранит путь к script и при
следующем lifecycle action запускает файл по этому пути заново. Активный
daemon автоматически не заменяется. Для текущего `-r2`, не меняющего
`proto_config` schema, достаточно отдельного controlled
`ifdown <interface>`/`ifup <interface>`. Если будущий release меняет dump
metadata или schema handler, release notes должны потребовать полный netifd
restart/reboot; обычный reload такую metadata не перечитывает.
