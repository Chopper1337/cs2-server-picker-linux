#!/bin/bash

# Function to unblock IP addresses using iptables
unblock_ip_addresses() {
    echo "Unblocking IP addresses using iptables..."
    while read -r ip; do
        sudo iptables -D INPUT -s "$ip" -j DROP
        echo "Unblocked IP address: $ip"
    done < blocked-ips.txt
    echo "All IP addresses unblocked successfully."
}

# Main function
main() {
    # Check if blocked-ips.txt file exists
    if [[ -f "blocked-ips.txt" ]]; then
        # Display the contents of blocked-ips.txt
        echo "Contents of blocked-ips.txt:"
        cat blocked-ips.txt

        # Prompt user if they want to unblock the IP addresses
        read -p "Do you want to unblock these IP addresses using iptables? (yes/no): " answer
        if [[ $answer == "yes" ]]; then
            unblock_ip_addresses
        else
            echo "IP addresses not unblocked."
        fi
    else
        echo "blocked-ips.txt file not found. No IP addresses to unblock."
    fi
}

# Execute main
main
