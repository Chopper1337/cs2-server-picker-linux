#!/usr/bin/env bash

# Function to print formatted messages
echo_fmt() {
	case $1 in
	"i") echo -e "\e[32m[INFO]\e[0m $2" ;;
	"e") echo -e "\e[31m[ERROR]\e[0m $2" ;;
	*) echo -e "[UNKNOWN] $2" ;;
	esac
}

# Function to fetch data from the API endpoint, filter out irrelevant data
fetch_data() {
	local API_ENDPOINT="https://api.steampowered.com/ISteamApps/GetSDRConfig/v1/?appid=730"
	curl -s "$API_ENDPOINT" | jq 'del(.success, .certs, .p2p_share_ip, .relay_public_key, .revoked_keys, .typical_pings) | del(.pops.can, .pops.ctu, .pops.eat, .pops.sha, .pops.tsn)' >/tmp/cs2_servers.json
}

read_data() {
	[[ ! -f /tmp/cs2_servers.json ]] && {
		echo_fmt "e" "Data file not found."
		exit 1
	}
	cat /tmp/cs2_servers.json
}

# Function to check for required dependencies
check_deps() {
	deps=(curl jq ping)
	for dep in ${deps[@]}; do
		which $dep >/dev/null || {
			echo_fmt "e" "Dependency '$dep' is not installed."
			exit 1
		}
	done
}

# Number of ICMP echo requests to send per relay IP
PING_COUNT=1
# How many relays to ping at once
PARALLEL=64
# Cache of best average ping per server, one "server,avg" line each (e.g. "ams,23")
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cs2-server-picker"
CACHE_FILE="$CACHE_DIR/pings.csv"

# Ping a single relay and, if it replies, print "server<TAB>ipv4<TAB>avg".
# Exported so xargs can call it in parallel worker shells.
ping_relay() {
	local server=$1 ip=$2 avg
	avg=$(ping -n -c "$PING_COUNT" -w 2 "$ip" 2>/dev/null | sed -n 's#.*= [0-9.]*/\([0-9.]*\)/.*#\1#p')
	[[ -n "$avg" ]] && printf '%s\t%s\t%s\n' "$server" "$ip" "$avg"
}
export -f ping_relay
export PING_COUNT

# Ping every relay of every server in parallel, report the lowest-latency relay
# per server, and cache the best average ping per server.
ping_servers() {
	local data=$(read_data)

	# One "server ipv4" pair per relay, fed to xargs for parallel pinging.
	local pairs
	pairs=$(jq -r '.pops | to_entries[]
		| select(.value.relays != null)
		| .key as $k | .value.relays[] | "\($k) \(.ipv4)"' <<<"$data")

	# Fan out: collect "server<TAB>ip<TAB>avg" for every relay that replied.
	local results
	results=$(xargs -P "$PARALLEL" -L1 bash -c 'ping_relay "$0" "$1"' <<<"$pairs")

	# Keep only the lowest-avg relay for each server.
	local best
	best=$(sort -t$'\t' -k1,1 -k3,3g <<<"$results" | awk -F'\t' '!seen[$1]++')

	printf '%-8s %-40s %-16s %s\n' "SERVER" "LOCATION" "BEST RELAY" "AVG ms"
	printf '%-8s %-40s %-16s %s\n' "------" "--------" "----------" "------"

	mkdir -p "$CACHE_DIR"
	: >"$CACHE_FILE"

	# Emit rows in Steam's original server order; cache each server's best avg.
	local server desc line ip avg
	while IFS=$'\t' read -r server desc; do
		[[ -z "$server" ]] && continue
		line=$(awk -F'\t' -v s="$server" '$1==s {print $2"\t"$3; exit}' <<<"$best")
		if [[ -z "$line" ]]; then
			printf '%-8s %-40s %s\n' "$server" "$desc" "(no reply)"
			continue
		fi
		ip=${line%%$'\t'*}
		printf -v avg '%.0f' "${line##*$'\t'}"
		printf '%-8s %-40s %-16s %s\n' "$server" "$desc" "$ip" "$avg"
		echo "$server,$avg" >>"$CACHE_FILE"
	done < <(jq -r '.pops | to_entries[]
		| select(.value.relays != null)
		| "\(.key)\t\(.value.desc // "?")"' <<<"$data")

	echo_fmt "i" "Cached best average pings to $CACHE_FILE"
}

help_usage() {
	echo "Usage: $0"
	echo ""
	echo "Pings every CS2 matchmaking datacenter relay and reports the lowest"
	echo "latency relay per datacenter, sorted by Steam's SDR server list."
	echo ""
	exit 1
}

# Main function
main() {
	case $1 in
	-h | --help) help_usage ;;
	esac

	check_deps
	fetch_data
	ping_servers
}

main "$@"
