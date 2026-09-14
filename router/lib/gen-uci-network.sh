#!/bin/sh
# Генерирует секции /etc/config/network для каждого сервера из servers.json —
# по одному интерфейсу AmneziaWG на сервер (proto 'amneziawg', пакет
# luci-proto-amneziawg из amnezia-vpn/amneziawg-openwrt).
#
# ВАЖНО: имена опций (awg_jc/awg_jmin/... и структура секции-пира
# amneziawg_<iface>) соответствуют схеме luci-proto-amneziawg на момент
# написания. Разные сборки awg-openwrt (amnezia-vpn/wadimk/Slava-Shchipunov и
# т.д.) могут называть опции чуть иначе — перед первым запуском сверьте с
# /lib/netifd/proto/amneziawg.sh на самом роутере (`cat` его и посмотрите
# json_add_string/json_get_var вызовы) и поправьте при расхождении.
#
# Использование: gen-uci-network.sh servers.json > network.awg-failover.uci

set -e
. /usr/share/libubox/jshn.sh

CONFIG_FILE="$1"
if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
	echo "Usage: $0 <servers.json>" >&2
	exit 1
fi

json_load_file "$CONFIG_FILE"
json_select servers

idx=1
while json_is_a "$idx" array || json_is_a "$idx" object; do
	json_select "$idx"

	json_get_var name name
	json_get_var priority priority
	json_get_var endpoint_host endpoint_host
	json_get_var endpoint_port endpoint_port
	json_get_var private_key private_key
	json_get_var public_key public_key
	json_get_var preshared_key preshared_key
	json_get_var address address
	json_get_var allowed_ips allowed_ips
	json_get_var mtu mtu
	json_get_var jc jc
	json_get_var jmin jmin
	json_get_var jmax jmax
	json_get_var s1 s1
	json_get_var s2 s2
	json_get_var s3 s3
	json_get_var s4 s4
	json_get_var h1 h1
	json_get_var h2 h2
	json_get_var h3 h3
	json_get_var h4 h4

	iface="awg_${name}"

	cat <<-EOF

	config interface '${iface}'
		option proto 'amneziawg'
		option private_key '${private_key}'
		list addresses '${address}'
		option mtu '${mtu:-1280}'
		option awg_jc '${jc}'
		option awg_jmin '${jmin}'
		option awg_jmax '${jmax}'
		option awg_s1 '${s1}'
		option awg_s2 '${s2}'
		option awg_s3 '${s3}'
		option awg_s4 '${s4}'
		option awg_h1 '${h1}'
		option awg_h2 '${h2}'
		option awg_h3 '${h3}'
		option awg_h4 '${h4}'
		option defaultroute '0'
		option delegate '0'

	config amneziawg_${iface} 'wgserver'
		option public_key '${public_key}'
		option endpoint_host '${endpoint_host}'
		option endpoint_port '${endpoint_port}'
		option preshared_key '${preshared_key}'
		list allowed_ips '${allowed_ips}'
		option persistent_keepalive '25'
		option route_allowed_ips '1'
	EOF

	json_select ..
	idx=$((idx + 1))
done
