# linux-watchdog — портируемый failover для ЛЮБОГО Linux-шлюза (не только OpenWrt)

Это ВТОРОЙ, отдельный от `router/` (mwan3/OpenWrt) вариант. Разница:

| | `router/` (mwan3) | `linux-watchdog/` |
|---|---|---|
| Прошивка | Только настоящий OpenWrt (UCI + пакет mwan3) | Любой обычный Linux: Debian/Ubuntu, Raspberry Pi OS, Entware — где есть bash + awg-quick |
| Сколько туннелей поднято | Все сразу, mwan3 просто меняет маршрут по умолчанию | Один за раз — down текущего, up следующего |
| Проверено вживую | Нет (синтаксис проверен, реального роутера не было) | Да, на боевом сервере AntiZapret (детект падения и переключение подтверждены; полный круг "переключились и новый сервер ответил" — с другой машины, см. `live-test.sh`) |
| Статус | Устарело как "primary" под Keenetic (см. ниже) | Основной кандидат под Entware/Keenetic |

## Про Keenetic конкретно

Заводская прошивка Keenetic (KeeneticOS) — это **не OpenWrt**, это отдельная
проприетарная Linux-based прошивка. Поэтому `router/` (UCI + mwan3) на
заводском Keenetic не встанет вообще — там нет ни UCI, ни mwan3, ни их
аналогов.

Два реальных пути на Keenetic:

1. **Entware** (штатная для Keenetic вещь: Общие настройки -> USB-накопитель
   с Entware, или через `opkg` после установки) — это отдельный от OpenWrt
   пакетный менеджер, даёт полноценный busybox/bash-окружение поверх
   заводской прошивки, БЕЗ переустановки самой прошивки. В этом окружении
   как раз и может работать `failover-watchdog.sh` — он не завязан на UCI,
   ему нужны только `bash`, `awg-quick` (пакет `amneziawg-tools`), `jq`,
   `curl`. **Неизвестно без проверки на вашей модели**: есть ли в фидах
   Entware готовый `amneziawg-tools`/`kmod-amneziawg` под архитектуру именно
   вашего Keenetic (MIPS/ARM/MT7621 и т.д.) — сборки under-the-hood это
   форк wireguard-tools с патчами обфускации, под экзотические архитектуры
   могут не собираться из коробки. Штатный WireGuard-клиент, который есть в
   GUI некоторых моделей Keenetic "из коробки" — это ванильный WireGuard,
   **без обфускации** (Jc/Jmin/Jmax/S1-S4/H1-H4), а обфускация — весь смысл
   AmneziaWG для обхода блокировок, так что штатный GUI-клиент тут не
   подходит.
2. **Перепрошивка в настоящий OpenWrt** — только если конкретная модель
   Keenetic есть в списке поддерживаемых устройств OpenWrt (далеко не все
   модели поддерживаются, особенно новые). Тогда открывается `router/`
   (mwan3) — штатный, проверенный временем подход, но: (а) теряется
   родной Keenetic-интерфейс/приложение, (б) это необратимо без
   доп.действий и рискованно (можно "окирпичить" устройство при ошибке),
   (в) отдельная история для каждой модели.

**Итог**: чтобы сказать что-то конкретное и безопасное — нужна точная модель
вашего Keenetic (например "Keenetic Giga KN-1010" или "Keenetic Peak
KN-2710"). По ней можно проверить: (1) есть ли Entware для неё, (2) есть ли
в её Entware-фиде amneziawg-tools под её процессор, (3) числится ли модель в
списке поддержки OpenWrt как запасной план. Без этого любой ответ — гадание
"должно быть похоже на другие модели".

Если Entware+amneziawg на конкретной модели не заведётся — резервный
вариант без роутера вообще: `linux-watchdog` на отдельном дешёвом
mini-PC/Raspberry Pi, который просто стоит рядом с роутером как
Ethernet-мост (роутер -> этот шлюз -> остальная сеть); тогда архитектура
процессора выбирается вами (любой x86/ARM с нормальной поддержкой пакетов),
и вопрос архитектуры отпадает полностью.

## Использование (на любом Linux, где это уже работает: сам сервер AntiZapret,
Raspberry Pi, Entware-Keenetic — если он потянет amneziawg-tools)

### 1. Разовая настройка — привязать устройство к пулу в панели

В панели: **Автопереключение** -> выбрать/создать пул -> добавить в него
серверы-узлы (Nodes) -> привязать клиента (вкладка клиента в пуле, тот же
`client_name`, что уже используется в AmneziaWG 2.0 для этого пользователя)
-> панель покажет `access_token` **один раз** — сохраните его, это ключ к
получению рабочих конфигов, храните как секрет.

### 2. Забрать конфиги с панели

```sh
apt-get install -y jq curl amneziawg-tools   # или opkg install ... на Entware
mkdir -p /root/antizapret-failover/confs
./fetch-config.sh https://<панель>/api <TOKEN> \
    /root/antizapret-failover/servers.json /root/antizapret-failover/confs
```

Это создаёт `servers.json` (приоритеты + health-check настройки пула) и
`confs/<имя-узла>.conf` (уже готовые клиентские конфиги AmneziaWG 2.0 —
ключи/endpoint/обфускация панель собрала сама).

### 3. Запустить watchdog

```sh
PANEL_API_BASE=https://<панель>/api PANEL_DEVICE_TOKEN=<TOKEN> \
    DEVICE_LABEL="$(hostname)" \
    ./failover-watchdog.sh /root/antizapret-failover/servers.json \
        /root/antizapret-failover/confs
```

`PANEL_API_BASE`/`PANEL_DEVICE_TOKEN`/`DEVICE_LABEL` — необязательные,
только для видимости статуса в панели (вкладка клиента в пуле покажет,
какой сервер активен и жив ли он с точки зрения ЭТОГО устройства). Само
переключение работает и без них, чисто по факту связи — панель тут
наблюдатель, не участник решения (специально, т.к. с точки зрения самой
панели сервер может выглядеть иначе, чем с точки зрения конкретного
устройства — see комментарий в верхнеуровневом README про "сервер
заблокирован — панель не обязательно видит это так же").

### 4. Автозапуск + периодическая пересинхронизация — systemd

```ini
# /etc/systemd/system/az-failover.service
[Unit]
Description=AntiZapret failover watchdog
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=PANEL_API_BASE=https://<панель>/api
Environment=PANEL_DEVICE_TOKEN=<TOKEN>
ExecStart=/root/antizapret-failover/failover-watchdog.sh \
    /root/antizapret-failover/servers.json /root/antizapret-failover/confs
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```ini
# /etc/systemd/system/az-failover-sync.service
[Unit]
Description=Sync failover config from panel

[Service]
Type=oneshot
ExecStart=/root/antizapret-failover/fetch-config.sh \
    https://<панель>/api <TOKEN> \
    /root/antizapret-failover/servers.json /root/antizapret-failover/confs
ExecStartPost=/bin/systemctl restart az-failover.service
```

```ini
# /etc/systemd/system/az-failover-sync.timer
[Unit]
Description=Periodic failover config sync

[Timer]
OnBootSec=1min
OnUnitActiveSec=15min

[Install]
WantedBy=timers.target
```

```sh
systemctl daemon-reload
systemctl enable --now az-failover.service az-failover-sync.timer
```

На Entware (без systemd, обычно procd/init.d от Keenetic или просто cron из
Entware) — тот же принцип: `fetch-config.sh` в cron раз в N минут +
`failover-watchdog.sh` в `/opt/etc/init.d/` как демон, перезапуск после
каждого fetch. Точный синтаксис — зависит от того, что именно на конкретной
модели Keenetic предоставляет Entware (crond есть почти всегда).
