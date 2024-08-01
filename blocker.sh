#!/bin/bash

deps=( curl jq )

for dep in ${deps[@]}
do 
  which $dep || exit
done

# Function to fetch data from the API endpoint, filter out irrelevant data, and save it to a temporary file
fetch_data() {
    local API_ENDPOINT="https://api.steampowered.com/ISteamApps/GetSDRConfig/v1/?appid=730"
    curl -s "$API_ENDPOINT" | jq 'del(.success, .certs, .p2p_share_ip, .relay_public_key, .revoked_keys, .typical_pings) | del(.pops.can, .pops.ctu, .pops.eat, .pops.sha, .pops.tsn)'
}

# Function to parse the JSON data and extract country/region names and IPs
parse_countries() {
    local data=$1
    jq -r '.pops | keys[]' <<< "$data"
}

# Function to get IP addresses by country
get_ips_by_country() {
    local country=$1
    local data=$2
    jq -r ".pops[\"$country\"].relays[].ipv4" <<< "$data"
}

# Function to save blocked IP addresses to a file
save_blocked_ips() {
    local blocked_ips=()
    local countries_to_block=("$@")
    local data=$1

    for country in "${countries_to_block[@]}"; do
        local ips=($(get_ips_by_country "$country" "$data"))
        for ip in "${ips[@]}"; do
            blocked_ips+=("$ip")
        done
    done

    # Save blocked IP addresses to a file named "blocked-ips.txt"
    echo "Blocked IP addresses:" > blocked-ips.txt
    for ip in "${blocked_ips[@]}"; do
        echo "$ip" >> blocked-ips.txt
    done

    echo "Blocked IP addresses saved to blocked-ips.txt"
}

# Function to block IP addresses using iptables
block_ip_addresses() {
    echo "Blocking IP addresses using iptables..."
    while read -r ip; do
        sudo iptables -A INPUT -s "$ip" -j DROP
        echo "Blocked IP address: $ip"
    done < blocked-ips.txt
    echo "All IP addresses blocked successfully."
}

# Main function
main() {
    # Fetch data from API endpoint
    local data=$(fetch_data)

    # Display list of countries
    echo "List of Countries:"
    echo "------------------"
    parse_countries "$data"

    # If command-line arguments are provided, save blocked IPs to file
    if [[ $# -gt 0 ]]; then
        save_blocked_ips "$data" "$@"
    else
        # Prompt user to enter countries to block
        read -p "Enter the countries you want to block (separated by space): " -a countries_to_block
        save_blocked_ips "$data" "${countries_to_block[@]}"
    fi

    # Display the contents of blocked-ips.txt
    echo "Contents of blocked-ips.txt:"
    cat blocked-ips.txt

    # Prompt user if they want to block the IP addresses
    read -p "Do you want to block these IP addresses using iptables? (yes/no): " answer
    if [[ $answer == "yes" ]]; then
        block_ip_addresses
    else
        echo "IP addresses not blocked."
    fi
}

# Execute main function with command-line arguments
main "$@"
