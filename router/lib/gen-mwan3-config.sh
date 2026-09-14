#!/bin/sh
# Генерирует секции /etc/config/mwan3: по одному "interface"+"member" на
# сервер (метрика = priority из servers.json, меньше = приоритетнее),
# одна policy со всеми members и одно правило "весь трафик по умолчанию идёт
# через эту policy". mwan3 сам следит за здоровьем через track_ip (см. секцию
# health_check в servers.json — пингуем НЕ сам сервер, а публичный адрес
# сквозь туннель) и переключает маршрут по умолчанию на следующий по
# приоритету member, когда текущий "падает" по своим down/up-порогам.
#
# Использование: gen-mwan3-config.sh servers.json > mwan3.awg-failover.uci

set -e
. /usr/share/libubox/jshn.sh

CONFIG_FILE="$1"
if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
	echo "Usage: $0 <servers.json>" >&2
	exit 1
fi

json_load_file "$CONFIG_FILE"

json_select health_check
json_get_var hc_target target
json_get_var hc_interval interval
json_get_var hc_timeout timeout
json_get_var hc_down down_threshold
json_get_var hc_up up_threshold
json_select ..

json_select servers

members=""
idx=1
while json_is_a "$idx" array || json_is_a "$idx" object; do
	json_select "$idx"
	json_get_var name name
	json_get_var priority priority
	iface="awg_${name}"
	member="${iface}_m1"
	members="${members} ${member}"

	cat <<-EOF

	config interface '${iface}'
		option enabled '1'
		option family 'ipv4'
		option track_ip '${hc_target:-1.1.1.1}'
		option track_method 'ping'
		option reliability '1'
		option count '1'
		option size '56'
		option max_ttl '60'
		option timeout '${hc_timeout:-3}'
		option interval '${hc_interval:-10}'
		option failure_interval '5'
		option recovery_interval '5'
		option down '${hc_down:-3}'
		option up '${hc_up:-3}'

	config member '${member}'
		option interface '${iface}'
		option metric '${priority}'
		option weight '1'
	EOF

	json_select ..
	idx=$((idx + 1))
done

echo
echo "config policy 'awg_failover'"
for m in $members; do
	echo "	list use_member '${m}'"
done

cat <<-EOF

config rule 'awg_failover_default'
	option dest_ip '0.0.0.0/0'
	option use_policy 'awg_failover'
	option sticky '1'
EOF
