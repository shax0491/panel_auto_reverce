#!/bin/bash
# Одноразовый скрипт живого теста failover-watchdog.sh на реальном сервере
# AntiZapret с реальным AmneziaWG 2.0. Создаёт ОДНОГО одноразового тестового
# клиента, гоняет watchdog (по умолчанию 90 секунд, переопределяется
# TEST_DURATION=N), затем полностью убирает за собой: гасит тестовые
# интерфейсы, удаляет тестового клиента через client.sh (unified delete,
# 2 — клиент одноразовый, всё равно все протоколы), печатает список
# реальных AWG2-клиентов до/после для сверки, что ничего лишнее не задето.
#
# Не трогает: существующих клиентов, admin-панель, реальные *2.conf
# серверные конфиги.
#
# ЧЕСТНО ПРО ОГРАНИЧЕНИЕ ЭТОГО ТЕСТА (проверено на реальном сервере
# 2026-09-14): половина "detect down -> switch" полностью подтверждена и
# воспроизводится стабильно. Вторая половина ("после переключения новый
# сервер отвечает OK") НЕ подтверждается на этом конкретном VPS — не из-за
# бага watchdog'а или конфигов, а потому что сервер не поддерживает hairpin
# NAT: клиент, запущенный на этой же машине, не может достучаться до
# публичного IP этой же машины вообще ни для чего (проверено независимо от
# AmneziaWG — обычный curl к собственной панели по публичному IP тоже висит
# до таймаута). Это ограничение хостинга, не софта. Полноценно проверить
# "переключились и заработало" можно только с ДРУГОЙ машины (телефон/роутер)
# — см. верхнеуровневый README проекта.

set -e

TEST_NAME="autoswitchtest$$"
WORK_DIR="/root/autoswitch-live-test"
WATCHDOG="/root/antizapret/failover-watchdog.sh"

echo "== Проверка зависимостей =="
command -v jq >/dev/null || { apt-get update -qq && apt-get install -y -qq jq; }
command -v awg-quick >/dev/null || { echo "awg-quick не найден — нативный AWG2 не установлен на этом сервере"; exit 1; }
command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl; }

echo "== Реальные AWG2-клиенты ДО теста =="
/root/antizapret/client.sh 3 2>&1 | sed -n '/AmneziaWG 2.0 client names:/,$p'

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "== Создаём одноразового тестового клиента: $TEST_NAME =="
/root/antizapret/client.sh 1 "$TEST_NAME" 3650

# vpn2 (полный туннель), не antizapret2 — antizapret2 намеренно узкий
# split-tunnel (только CIDR заблокированных в РФ ресурсов), произвольный
# health-check адрес вроде 1.1.1.1 туда в принципе не попадает — это не
# баг, так и должен работать режим "АнтиЗапрет" в этом проекте.
REAL_CONF="$(find /root/antizapret/client/amneziawg2/vpn -iname "vpn2-${TEST_NAME}-*-am2.conf" | head -n1)"
if [ -z "$REAL_CONF" ] || [ ! -f "$REAL_CONF" ]; then
	echo "Не нашёл сгенерированный профиль для ${TEST_NAME} в /root/antizapret/client/amneziawg2/vpn"
	exit 1
fi
echo "Найден профиль: $REAL_CONF"

echo "== Собираем два тестовых конфига (реальный сервер + заведомо недоступный) =="
mkdir -p confs
# Сужаем AllowedIPs с 0.0.0.0/0 до health-check-адреса — full-tunnel клиент
# НА ТОМ ЖЕ сервере, по SSH к которому мы подключены, рискован для текущей
# SSH-сессии; узкий /32 маршрут её не затрагивает вообще.
# Также убираем I1-I5 (маскировка первого пакета) — установленная на этом
# сервере amneziawg-go (userspace fallback, кернел-модуль не загружен) не
# парсит пустое значение вида "I2 =" из части masquerade-пресетов шаблона
# client.sh — для проверки самого механизма переключения обфускация первого
# пакета не нужна.
sed -E 's#AllowedIPs = .*#AllowedIPs = 1.1.1.1/32#' "$REAL_CONF" | grep -vE '^I[1-5][[:space:]]*=' > "confs/real.conf"
# Тот же клиент/ключи, но порт заведомо не слушается никем — имитация
# "сервер лёг", ничего реального не трогаем.
sed -E 's#AllowedIPs = .*#AllowedIPs = 1.1.1.1/32#; s/(Endpoint = [^:]+):[0-9]+/\1:1/' "$REAL_CONF" | grep -vE '^I[1-5][[:space:]]*=' > "confs/down.conf"

cat > servers.json <<JSON
{
  "health_check": { "target": "1.1.1.1", "interval": 5, "timeout": 3, "down_threshold": 2, "up_threshold": 2 },
  "servers": [
    { "name": "down", "priority": 1 },
    { "name": "real", "priority": 2 }
  ]
}
JSON

echo "== Запуск watchdog (старт на заведомо нерабочем 'down') =="
chmod +x "$WATCHDOG" 2>/dev/null || true
timeout "${TEST_DURATION:-90}" bash "$WATCHDOG" servers.json confs/ 2>&1 | tee watchdog.log || true

echo
echo "== Итог теста =="
switched=$(grep -c "ПЕРЕКЛЮЧЕНИЕ: down -> real" watchdog.log || true)
ok_after_switch=$(grep -A5 "ПЕРЕКЛЮЧЕНИЕ: down -> real" watchdog.log | grep -c "^\[.*\] OK: real$" || true)
if [ "${switched:-0}" -ge 1 ]; then
	echo "Обнаружение недоступности 'down' и решение о переключении -> ПОДТВЕРЖДЕНО"
else
	echo "Переключение НЕ произошло за отведённое время — см. лог"
fi
if [ "${ok_after_switch:-0}" -ge 1 ]; then
	echo "'real' подтверждён здоровым после переключения (OK: ${ok_after_switch} раз)"
else
	echo "'real' не подтверждён здоровым за отведённое время (см. верхний комментарий про hairpin NAT этого сервера — ожидаемо при тесте с этой же машины)"
fi

echo "== Гасим тестовые интерфейсы (на всякий случай, если watchdog не успел/завис) =="
awg-quick down confs/real.conf 2>&1 || true
awg-quick down confs/down.conf 2>&1 || true

echo "== Удаляем тестового клиента $TEST_NAME (все протоколы, он одноразовый) =="
/root/antizapret/client.sh 2 "$TEST_NAME" 2>&1 || true

echo "== Реальные AWG2-клиенты ПОСЛЕ теста (должно совпадать со списком ДО, без $TEST_NAME) =="
/root/antizapret/client.sh 3 2>&1 | sed -n '/AmneziaWG 2.0 client names:/,$p'

cd /root
rm -rf "$WORK_DIR"
