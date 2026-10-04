# GovechoBSD — FreeBSD + GNOME от ZHBR-228
Полноценная BSD-редакция govechoOS: ядро FreeBSD 14.1, рабочий стол GNOME, ZFS с снапшотами, Linuxulator для flatpak из Debian-мира, фирменные утилиты gov*.

## Состав системы
| Компонент | Назначение |
|---|---|
| src/govinit.c | init-совместимый сервис-менеджер (PID 1) |
| src/govecho.c | echo с брендом (-s banner/loud) |
| src/govwelcome.c | приветственный экран при входе |
| src/govctl.c | консоль управления: status/info/apps/gnome tidy |
| src/govpkg.c | пакетный менеджер: pkg(8) + flatpak через Linuxulator |
| src/govzfs.c | **новое**: управление ZFS-пулом, снапшоты, rollback, boot-env |
| bsd/* | rc.conf, loader.conf, sysctl.conf (BBR+ARC), make.conf |
| overlay/ | motd-баннер, dconf-профиль GNOME (тёмная тема, баннер логина), алиасы профиля |
| config/packages.freebsd.list | полный состав: GNOME, Firefox, Thunderbird, LibreOffice, VLC, htop, fish… |
| scripts/build_bsd.sh | сборка live/DVD ISO образа |
| scripts/install_bsd.sh | установка на диск: GPT+ZFS-pool+датасеты+снапшот @install-base |

## Быстрый старт
```bash
sudo ./scripts/build_bsd.sh        # собрать образ (нужен FreeBSD-хост)
sudo ./scripts/install_bsd.sh ada0 # установить на диск
govzfs snap create pre-update      # моментальный снимок перед обновлением
govzfs rollback pre-update         # откат за секунды (Time Machine-style)
gp update                          # обновление через pkg
gtidy                              # «чистота GNOME» одним кликом
```

Лицензия MIT · Автор **ZHBR-228** · Родительский проект: [govnechoOS](https://github.com/ZHBR-228/govnechoOS)
