#!/bin/bash
# Портируемый (любой обычный Linux, НЕ OpenWrt) watchdog автопереключения —
# альтернатива router/ (mwan3) для тех, у кого шлюз/роутер — обычный Linux
# (Raspberry Pi, mini-PC, VPS-в-режиме-шлюза), а не прошивка OpenWrt.
#
# В отличие от mwan3-варианта, который держит несколько интерфейсов поднятыми
# одновременно и просто переключает маршрут по умолчанию, здесь поднят ровно
# один awg-quick туннель за раз — переключение = down текущего + up следующего.
# Проще модель, для одного шлюза-клиента вполне достаточно.
#
# Зависимости: awg-quick (amneziawg-tools), jq, curl.
# Использование:
#   failover-watchdog.sh servers.json /path/to/confs/
# где /path/to/confs/<name>.conf — уже сгенерированные awg-quick клиентские
# конфиги под каждый сервер из servers.json (имя файла = поле "name").

set -u

SERVERS_JSON="${1:?Usage: $0 servers.json confs-dir}"
CONF_DIR="${2:?Usage: $0 servers.json confs-dir}"

log() { echo "[$(date '+%F %T')] $*"; }

TARGET=$(jq -r '.health_check.target' "$SERVERS_JSON")
INTERVAL=$(jq -r '.health_check.interval' "$SERVERS_JSON")
TIMEOUT=$(jq -r '.health_check.timeout' "$SERVERS_JSON")
DOWN_THRESHOLD=$(jq -r '.health_check.down_threshold' "$SERVERS_JSON")

mapfile -t NAMES < <(jq -r '.servers | sort_by(.priority) | .[].name' "$SERVERS_JSON")

if [ "${#NAMES[@]}" -lt 1 ]; then
	log "servers.json: нет ни одного сервера"
	exit 1
fi

iface_exists() {
	ip link show "$1" >/dev/null 2>&1
}

# Вывод awg-quick идёт в лог через `| while read`, а это теряет его реальный
# exit code (пайп даёт статус последней команды — самого while). Из-за этого
# раньше даже упавший awg-quick (например, конфиг не распарсился) молча
# считался успехом, и health-check дальше нечаянно проверял обычный интернет
# сервера мимо туннеля. Поэтому здесь отдельно, явно проверяем, что
# интерфейс реально появился (ip link show) — это и есть настоящий сигнал
# успеха/провала up, не exit code пайпа.
bring_up() {
	local name="$1"
	awg-quick up "${CONF_DIR}/${name}.conf" 2>&1 | while IFS= read -r line; do log "awg-quick up ${name}: $line"; done
	if ! iface_exists "$name"; then
		log "ОШИБКА: интерфейс ${name} не поднялся (см. вывод awg-quick выше)"
		return 1
	fi
	log "диагностика: ip route get ${TARGET} -> $(ip route get "$TARGET" 2>&1 | tr '\n' ' ')"
	return 0
}

bring_down() {
	local name="$1"
	awg-quick down "${CONF_DIR}/${name}.conf" 2>&1 | while IFS= read -r line; do log "awg-quick down ${name}: $line"; done
}

# Пинг НЕ самого VPN-сервера (ICMP на серверах отключен) — сквозь текущий
# туннель проверяем надёжный публичный HTTPS-адрес. -k (игнорировать
# сертификат) — при обращении по голому IP (не по имени) SNI/сертификат
# всё равно не совпадёт, а нас интересует только факт доставки пакетов,
# не подлинность сертификата. Сначала проверяем, что интерфейс вообще
# существует — иначе curl уходит через обычный маршрут по умолчанию мимо
# туннеля и врёт про здоровье несуществующего соединения.
healthy() {
	local iface="$1"
	iface_exists "$iface" || return 1
	# --interface привязывает исходящий сокет ИМЕННО к этому устройству
	# (SO_BINDTODEVICE), а не полагается на то, что таблица маршрутизации
	# отправит пакет туда, куда мы думаем — так однозначно проверяется
	# здоровье именно этого туннеля, а не "куда-то да дойдёт".
	curl -sk -o /dev/null --interface "$iface" --max-time "$TIMEOUT" "https://${TARGET}/"
}

index_of() {
	local needle="$1" i
	for i in "${!NAMES[@]}"; do
		[ "${NAMES[$i]}" = "$needle" ] && { echo "$i"; return; }
	done
	echo 0
}

cleanup() {
	log "Остановка — гасим текущий туннель ($current)"
	bring_down "$current"
	exit 0
}
trap cleanup INT TERM

current="${NAMES[0]}"
bring_up "$current" || true

consecutive_failures=0
settle=0

log "Старт. Приоритет серверов: ${NAMES[*]}. Активен: $current"

while true; do
	if healthy "$current"; then
		consecutive_failures=0
		[ "$settle" -gt 0 ] && settle=$((settle - 1))
		log "OK: $current"
	elif [ "$settle" -gt 0 ]; then
		log "Устанавливается: $current (даём время на хендшейк, осталось попыток: $settle)"
	else
		consecutive_failures=$((consecutive_failures + 1))
		log "НЕТ СВЯЗИ ($consecutive_failures/$DOWN_THRESHOLD): $current"
		if [ "$consecutive_failures" -ge "$DOWN_THRESHOLD" ]; then
			current_index=$(index_of "$current")
			next_index=$(((current_index + 1) % ${#NAMES[@]}))
			next="${NAMES[$next_index]}"
			log "ПЕРЕКЛЮЧЕНИЕ: $current -> $next"
			bring_down "$current"
			bring_up "$next" || true
			current="$next"
			consecutive_failures=0
			settle=$DOWN_THRESHOLD
		fi
	fi
	sleep "$INTERVAL"
done
