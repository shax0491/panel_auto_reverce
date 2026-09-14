#!/bin/bash
# Забирает список серверов + готовые клиентские .conf у панели
# (AdminPanelAZ_new, фича "Автопереключение" / failover_pools) и раскладывает
# их в формате, который ожидает failover-watchdog.sh — то есть заменяет
# ручное заполнение servers.json и confs/*.conf на автоматическую синхронизацию.
#
# Панель отдаёт УЖЕ полностью готовые .conf (ключи, endpoint, обфускация) —
# на этой стороне ничего собирать не нужно, только сохранить как есть.
#
# Использование:
#   fetch-config.sh <panel_api_base> <device_token> <servers.json> <confs-dir>
# Пример:
#   fetch-config.sh https://panel.example.com/api aBcD1234...xyz \
#       /root/antizapret-failover/servers.json /root/antizapret-failover/confs
#
# panel_api_base — адрес API панели ДО /public/failover/... (обычно
#   https://<ваш-домен-панели>/api, если панель не поднята под кастомным
#   под-путём; уточняется в Настройках панели).
# device_token — access_token привязки клиента к пулу, панель показывает его
#   один раз при создании привязки (Автопереключение -> пул -> привязать
#   клиента). Держите его как секрет — по нему выдаются рабочие .conf.
#
# Рассчитан на периодический запуск (cron/systemd timer), НЕ на запуск внутри
# самого watchdog-цикла — конфиги на диске меняются редко (при добавлении/
# удалении узла в пуле), а health-check должен крутиться часто. Скрипт
# перезаписывает servers.json и confs/*.conf атомарно (через временный файл +
# mv), поэтому safe гонять его, пока watchdog уже работает — он просто
# подхватит новые файлы на следующем перезапуске watchdog'а (см. README).

set -u

PANEL_API_BASE="${1:?Usage: $0 panel_api_base device_token servers.json confs-dir}"
DEVICE_TOKEN="${2:?Usage: $0 panel_api_base device_token servers.json confs-dir}"
SERVERS_JSON="${3:?Usage: $0 panel_api_base device_token servers.json confs-dir}"
CONF_DIR="${4:?Usage: $0 panel_api_base device_token servers.json confs-dir}"

log() { echo "[$(date '+%F %T')] fetch-config: $*"; }

for bin in curl jq; do
	command -v "$bin" >/dev/null 2>&1 || { log "ОШИБКА: не найден $bin"; exit 1; }
done

URL="${PANEL_API_BASE%/}/public/failover/${DEVICE_TOKEN}/config"

RESPONSE=$(curl -fsS --max-time 15 "$URL") || {
	log "ОШИБКА: не удалось получить конфиг с панели ($URL)"
	exit 1
}

echo "$RESPONSE" | jq -e '.servers | length > 0' >/dev/null 2>&1 || {
	log "ОШИБКА: панель вернула пустой список серверов (пул выключен, нет живых узлов, или нет ни одного успешно собранного .conf — см. панель)"
	exit 1
}

mkdir -p "$CONF_DIR"

# servers.json — только то, что реально читает failover-watchdog.sh
TMP_SERVERS=$(mktemp)
echo "$RESPONSE" | jq '{
	health_check: {
		target: .health_check_target,
		interval: .health_check_interval_s,
		timeout: .health_check_timeout_s,
		down_threshold: .down_threshold
	},
	servers: [.servers[] | {name: .name, priority: .priority}] | sort_by(.priority)
}' >"$TMP_SERVERS"
mv "$TMP_SERVERS" "$SERVERS_JSON"

# По одному .conf на сервер, имя файла = поле "name" (как ожидает watchdog).
# Сначала во временную директорию, потом одним махом поверх старой — чтобы
# работающий watchdog никогда не увидел частично записанный .conf.
TMP_CONF_DIR=$(mktemp -d)
NAMES=$(echo "$RESPONSE" | jq -r '.servers[].name')
while IFS= read -r name; do
	[ -n "$name" ] || continue
	echo "$RESPONSE" | jq -r --arg n "$name" '.servers[] | select(.name == $n) | .conf' >"${TMP_CONF_DIR}/${name}.conf"
	chmod 600 "${TMP_CONF_DIR}/${name}.conf"
done <<<"$NAMES"

find "$CONF_DIR" -maxdepth 1 -name '*.conf' -exec rm -f {} + 2>/dev/null
mv "$TMP_CONF_DIR"/*.conf "$CONF_DIR"/ 2>/dev/null
rmdir "$TMP_CONF_DIR" 2>/dev/null

COUNT=$(echo "$NAMES" | grep -c . || true)
log "Готово: ${COUNT} сервер(ов) сохранено в ${CONF_DIR}, приоритеты в ${SERVERS_JSON}"
