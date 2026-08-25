# Changelog

Все заметные изменения проекта документируются в этом файле.

## Unreleased

- первый userspace-only package set для OpenWrt 25.12.5;
- netifd/UCI protocol `amneziawg3`;
- LuCI interface и peer editor для параметров AWG 3.1;
- collision-safe CLI `awg3`/`awg-quick3`;
- опциональные стандартные aliases;
- pinned SDK build, signed APK feed и GitHub Pages release workflow;
- read-only preflight, rollback и диагностика.
- fail-closed policy `Jc/Jmin/Jmax` до запуска userspace daemon;
- LuCI key RPC без private key в argv или RPC parameters;
- first-install-only installer с exact package/version rollback и безопасными
  временными файлами;
- exact allowlist `board_name=cudy,tr3000-v1`;
- `auto=0` для staged configuration и отдельный netifd discovery gate после
  install/upgrade;
- collision-safe install/upgrade/uninstall lifecycle init facade;
- pre-deinstall teardown while the netifd handler is still installed, with the
  APK 3 non-veto limitation documented;
- OpenWrt package release `-r2` для исправлений release-readiness review.
