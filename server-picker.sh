#!/usr/bin/env bash

# Function to print formatted messages
echo_fmt() {
	case $1 in
	"i") echo -e "\e[32m[INFO]\e[0m $@" ;;
	"e") echo -e "\e[31m[ERROR]\e[0m $@" ;;
	*) echo -e "[UNKNOWN] $@" ;;
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

# Function to parse the JSON data and extract server/region names and IPs in a neat format
list_servers() {
	local data=$(read_data)
	jq -r '.pops | keys[]' <<<"$data" | column -c 80
}

# Function to get IP addresses by server
get_ips_by_server() {
	local server=$1
	local data=$(read_data)
	jq -r ".pops[\"$server\"].relays[].ipv4" <<<"$data"
}

# Function to check for required dependencies
check_deps() {
	deps=(curl jq iptables)
	for dep in ${deps[@]}; do
		which $dep >/dev/null || {
			echo_fmt "e" "Dependency '$dep' is not installed."
			exit 1
		}
	done
}

# Function to block IP addresses using iptables
block_ips() {

	[[ $# -lt 2 ]] && {
		echo_fmt "e" "No server names provided to block"
		help_usage
	}

	local data=$(read_data)

	for server in "$@"; do
		ips=$(get_ips_by_server "$server" "$data")
		for ip in $ips; do
			sudo iptables -A OUTPUT -d "$ip" -j DROP
			echo_fmt "i" "Blocked IP: $ip for server: $server"
		done
	done
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
	echo "  -l, --list-servers         List available servers/regions"
	echo "  -b, --block [SERVER...]    Block IPs for specified servers"
	echo "  -u, --unblock              Unblock all previously blocked IPs"
	echo "  -lb, --list-blocked        List currently blocked IPs"
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
