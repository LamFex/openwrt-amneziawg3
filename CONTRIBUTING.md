# Вклад в проект

Первый релиз имеет намеренно узкий scope: OpenWrt 25.12.5,
`aarch64_cortex-a53`, Cudy TR3000 v1 и userspace `amneziawg-go`.
Pull request, расширяющий версии или архитектуры, должен включать отдельный SDK
build, устройство/эмуляторные evidence и обновлённую матрицу поддержки.

`PKG_MAINTAINER`/`LUCI_MAINTAINER` пока намеренно указывают коллективное имя
`AWG OpenWrt3 contributors`: у локального проекта ещё нет подтверждённых
публичных координат владельца, и проект не выдумывает имя или email. До первого
stable release владелец репозитория должен заменить его на проверяемое
`Name <email>` либо документированную team address. Security reports до этого
момента принимаются только через GitHub Security Advisories после публикации.

Перед pull request:

```sh
make verify
./scripts/verify-upstream.sh
./scripts/verify-patches.sh
```

Требования:

- не добавлять private keys, profiles, IP credentials или Actions secrets;
- не перехватывать ownership процесса у netifd;
- не создавать временные plaintext-файлы с tunnel configuration;
- не устанавливать стандартные `awg` aliases из default meta-package;
- не включать `route_allowed_ips` по умолчанию;
- сохранять code identifiers, comments и errors на английском;
- обновлять русскую пользовательскую документацию.
- проверять LuCI и backend одинаковыми граничными fixture для
  `Jc/Jmin/Jmax`;
- не добавлять network restart/reboot/ifup в package hooks или installer.

Device tests выполняются только по
[router validation plan](docs/router-validation.md) и после явного
подтверждения владельца роутера.
