#!/bin/sh
# Устанавливает AmneziaWG + mwan3 на OpenWrt и настраивает автопереключение
# между серверами, описанными в servers.json (см. servers.example.json).
#
# Использование (на самом роутере, по SSH):
#   scp servers.json lib/gen-uci-network.sh lib/gen-mwan3-config.sh install.sh root@router:/tmp/
#   ssh root@router 'cd /tmp && sh install.sh servers.json'
#
# Идемпотентно по конфигам (uci import добавляет секции, не трогая
# существующие lan/wan), НЕ идемпотентно по пакетам — opkg install уже
# установленных пакетов просто ничего не делает, это нормально.

set -e

CONFIG_FILE="${1:-servers.json}"
if [ ! -f "$CONFIG_FILE" ]; then
	echo "Не найден $CONFIG_FILE. Скопируйте свой servers.json рядом со скриптом или укажите путь первым аргументом." >&2
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== Проверка архитектуры пакета =="
ARCH="$(opkg print-architecture | awk '{print $2}' | tail -n1)"
echo "Архитектура: ${ARCH:-неизвестна} — сверьте с релизами amnezia-vpn/amneziawg-openwrt, если opkg update/install ниже не найдёт пакет в стандартных репозиториях."

echo "== Установка пакетов =="
opkg update
opkg install kmod-amneziawg amneziawg-tools luci-proto-amneziawg mwan3 jshn

echo "== Бэкап текущих конфигов =="
cp /etc/config/network "/etc/config/network.bak-$(date +%s)"
cp /etc/config/mwan3 "/etc/config/mwan3.bak-$(date +%s)" 2>/dev/null || true

echo "== Генерация конфигов из ${CONFIG_FILE} =="
sh "${SCRIPT_DIR}/lib/gen-uci-network.sh" "$CONFIG_FILE" > /tmp/network.awg-failover.uci
sh "${SCRIPT_DIR}/lib/gen-mwan3-config.sh" "$CONFIG_FILE" > /tmp/mwan3.awg-failover.uci

echo "== Импорт в uci =="
uci import network < /tmp/network.awg-failover.uci
uci import mwan3 < /tmp/mwan3.awg-failover.uci
uci commit network
uci commit mwan3

echo "== Применение =="
/etc/init.d/network reload
/etc/init.d/mwan3 enable
/etc/init.d/mwan3 restart

echo
echo "Готово. Проверить состояние переключения:"
echo "  mwan3 status"
echo "  mwan3 interfaces"
echo "  logread -f | grep mwan3"
echo
echo "Если mwan3 не видит интерфейсы — почти наверняка расхождение в именах"
echo "опций luci-proto-amneziawg с тем, что сгенерировал gen-uci-network.sh"
echo "(см. комментарий в начале этого файла). Сверьте руками:"
echo "  cat /lib/netifd/proto/amneziawg.sh"
