# Безопасность Jc/Jmin/Jmax

Эти ограничения относятся к package-managed пути UCI → netifd. Backend
проверяет их до запуска `amneziawg-go`, поэтому ручное редактирование UCI не
может обойти политику LuCI.

## Что делает upstream

Закреплённый `amneziawg-tools` 3.1.20260812 разбирает каждое из полей как
независимое `uint16`, то есть формально принимает значения до 65535. При этом
`amneziawg-go` 3.1.20260814 в `Device.JunkPackets()`:

1. читает `Jmin`, `Jmax` и `Jc` без проверки их взаимосвязи;
2. создаёт по одному `[]byte` на каждый junk packet;
3. вычисляет длину как `Jmin + fastrandn(Jmax - Jmin)`.

Если `Jmin >= Jmax`, вычитание и вызов генератора диапазона небезопасны. При
больших `Jc` и `Jmax` один handshake способен запросить опасный объём heap.

Источники:

- [pinned Go allocation loop](https://github.com/amnezia-vpn/amneziawg-go/blob/v3.1.20260814/device/noise-protocol.go#L632-L642);
- [pinned tools uint16 parser](https://github.com/amnezia-vpn/amneziawg-tools/blob/v3.1.20260812/src/config.c#L395-L411)
  и [независимый разбор трёх полей](https://github.com/amnezia-vpn/amneziawg-tools/blob/v3.1.20260812/src/config.c#L489-L500);
- [официальные пределы AmneziaWG](https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/blob/46803204e7ec3b068199cd671143bec661d3fe21/README.md#configuration);
- [официальный генератор профиля](https://github.com/amnezia-vpn/amnezia-client/blob/707266124452c566e8a723633759502221542901/client/core/installers/awgInstaller.cpp#L37-L42).

## Политика первого релиза

Разрешено либо не задавать всю тройку, либо задать все три каноническими
неотрицательными десятичными целыми:

| Параметр | Разрешено |
|---|---:|
| `Jc` | 1…128 |
| `Jmin` | 0…1279 |
| `Jmax` | 1…1280 |

Дополнительно обязательно `Jmin < Jmax` и
`Jc × Jmax <= 163840` байт. Пределы 128 и 1280 взяты из официального
описания AmneziaWG, а не выбраны локально. Последняя проверка является явным
worst-case allocation guard и остаётся в backend даже при изменении отдельных
лимитов в будущем.

При максимуме `Jc=128`, `Jmin=1279`, `Jmax=1280` текущий Go-код запросит не
более 128 × 1279 = **163712 байт** backing buffers за один вызов. Сам бюджет
ограничивает сумму верхних границ значением **163840 байт**. В эту цифру не
входят заголовки slice, metadata и округление size classes Go allocator;
одновременно выполняющиеся handshakes также умножают расход. Поэтому обычным
профилям следует оставаться около upstream-рекомендаций, а не использовать
максимумы без необходимости.

Официальный client generator в зафиксированном состоянии создаёт `Jc=4…6`,
`Jmin=10`, `Jmax=50`. Пакет допускает более широкий официальный диапазон для
совместимости с уже существующими профилями.

## Намеренно запрещено

- частично заполненная тройка;
- знак, whitespace, диапазон или иная неканоническая запись;
- `Jc=0` при явно заданной тройке;
- равные `Jmin` и `Jmax`;
- значения 65535, хотя parser tools способен их представить;
- всё, что превышает официальный предел или allocation budget.

LuCI повторяет те же правила для ранней подсказки. Authoritative решение
принимает `/lib/netifd/proto/amneziawg3.sh`. Команды `uci set`/`uci import` не
активируют интерфейс сами по себе: проверка происходит при `ifup` или renew и
завершается до daemon/process/network updates. Низкоуровневой командой
`/usr/libexec/amneziawg3/awg` не следует управлять netifd-интерфейсом вручную.
