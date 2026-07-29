#!/usr/bin/env bash

# Function to print formatted messages
echo_fmt() {
	case $1 in
	"i") echo -e "\e[32m[INFO]\e[0m $2" ;;
	"e") echo -e "\e[31m[ERROR]\e[0m $2" ;;
	*) echo -e "[UNKNOWN] $2" ;;
	esac
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

# Ping every relay of every server in parallel and cache the lowest average
# ping per server as "server,avg" lines (e.g. "ams,23").
update_cache() {
	local data=$(read_data)

	# One "server ipv4" pair per relay, fed to xargs for parallel pinging.
	local pairs
	pairs=$(jq -r '.pops | to_entries[]
		| select(.value.relays != null)
		| .key as $k | .value.relays[] | "\($k) \(.ipv4)"' <<<"$data")

	# Fan out; keep only the lowest-avg relay per server.
	local results
	results=$(xargs -P "$PARALLEL" -L1 bash -c 'ping_relay "$0" "$1"' <<<"$pairs")

	mkdir -p "$CACHE_DIR"
	sort -t$'\t' -k1,1 -k3,3g <<<"$results" \
		| awk -F'\t' '!seen[$1]++ {printf "%s,%.0f\n", $1, $3}' >"$CACHE_FILE"

	echo_fmt "i" "Cached average pings for $(wc -l <"$CACHE_FILE") servers to $CACHE_FILE"
}

# Build the cache only if it does not exist yet.
ensure_cache() {
	[[ -f "$CACHE_FILE" ]] || {
		echo_fmt "i" "No ping cache found, building it first..."
		update_cache
	}
}

# Function to parse the JSON data and extract server/region names in a neat
# format. When a ping cache exists, show it as a table sorted by latency.
list_servers() {
	local data=$(read_data)

	# server<TAB>friendly name, one per line
	local rows
	rows=$(jq -r '.pops | to_entries[] | "\(.key)\t\(.value.desc // "?")"' <<<"$data")

	[[ ! -f "$CACHE_FILE" ]] && {
		printf '%-8s %s\n' "SERVER" "LOCATION"
		printf '%-8s %s\n' "------" "--------"
		awk -F'\t' '{printf "%-8s %s\n", $1, $2}' <<<"$rows"
		return
	}

	printf '%-8s %-9s %s\n' "SERVER" "PING(ms)" "LOCATION"
	printf '%-8s %-9s %s\n' "------" "--------" "--------"
	while IFS=$'\t' read -r server desc; do
		local ping
		ping=$(awk -F, -v s="$server" '$1 == s {print $2}' "$CACHE_FILE")
		# Prefix a numeric sort key (uncached servers sort last), stripped after sorting.
		printf '%s\t%-8s %-9s %s\n' "${ping:-999999}" "$server" "${ping:-—}" "$desc"
	done <<<"$rows" | sort -n | cut -f2-
}

# Function to get IP addresses by server
get_ips_by_server() {
	local server=$1
	local data=$(read_data)
	jq -r ".pops[\"$server\"].relays[].ipv4" <<<"$data"
}

# Function to check for required dependencies
check_deps() {
	deps=(curl jq iptables ping)
	for dep in ${deps[@]}; do
		which $dep >/dev/null || {
			echo_fmt "e" "Dependency '$dep' is not installed."
			exit 1
		}
	done
}

# Function to block IP addresses using iptables for a list of server names
block_named_servers() {
	local data=$(read_data)

	for server in "$@"; do
		ips=$(get_ips_by_server "$server" "$data")
		for ip in $ips; do
			sudo iptables -A OUTPUT -d "$ip" -j DROP
			echo_fmt "i" "Blocked IP: $ip for server: $server"
		done
	done
}

# Handler for --block: block the server names passed on the command line
block_ips() {
	shift # drop the --block/-b flag
	[[ $# -lt 1 ]] && {
		echo_fmt "e" "No server names provided to block"
		help_usage
	}
	block_named_servers "$@"
}

# Block all cached servers whose average ping is above/below a threshold.
# $1 = comparison ("over" or "under"), $2 = threshold in ms.
block_by_ping() {
	local cmp=$1 threshold=$2

	[[ "$threshold" =~ ^[0-9]+$ ]] || {
		echo_fmt "e" "Ping threshold must be a whole number of milliseconds"
		help_usage
	}

	ensure_cache

	local op servers
	[[ "$cmp" == "over" ]] && op=">" || op="<"
	servers=$(awk -F, -v n="$threshold" "\$2 $op n {print \$1}" "$CACHE_FILE")

	[[ -z "$servers" ]] && {
		echo_fmt "i" "No cached servers with ping $cmp ${threshold}ms"
		return
	}

	block_named_servers $servers
}

# Function to unblock IP addresses using iptables
unblock_ips() {
  # TODO: Find a way to avoid using grep and awk here
	local blocked_ips=$(sudo iptables -L OUTPUT -n | grep DROP | awk '{print $5}')
	local data=$(read_data)

	for ip in $blocked_ips; do
		[[ -z "$ip" ]] && continue
		echo "$data" | jq '.pops | to_entries[] | select(.value.relays != null) | .value.relays[] | select(.ipv4 == "$ip")' >/dev/null || continue
		echo_fmt "i" "Unblocking IP: $ip"
		sudo iptables -D OUTPUT -d "$ip" -j DROP && echo_fmt "i" "Unblocked IP: $ip"
	done

}

list_blocked_ips() {
	sudo iptables -L OUTPUT -v -n | grep DROP
}

help_usage() {
	echo "Usage: $0 [OPTION]"
	echo ""
	echo "Options:"
	echo "  -l, --list-servers         List available servers/regions (with cached ping)"
	echo "  -b, --block [SERVER...]    Block IPs for specified servers"
	echo "      --block-over N         Block servers with cached ping over N ms"
	echo "      --block-under N        Block servers with cached ping under N ms"
	echo "  -u, --unblock              Unblock all previously blocked IPs"
	echo "  -lb, --list-blocked        List currently blocked IPs"
	echo "  -c, --update-cache         Ping all servers and cache their average ping"
	echo ""
	exit 1
}

# Main function
main() {

	# check dependencies
	check_deps

	# fetch API data
	fetch_data

	case $1 in
	--list-servers | -l)
		list_servers
		;;
	--block | -b)
		block_ips "$@"
		;;
	--block-over)
		block_by_ping "over" "$2"
		;;
	--block-under)
		block_by_ping "under" "$2"
		;;
	--update-cache | -c)
		update_cache
		;;
	--unblock | -u)
		unblock_ips
		;;
	--list-blocked | -lb)
		list_blocked_ips
		;;
	*)
		help_usage
		;;
	esac

}

main "$@"
