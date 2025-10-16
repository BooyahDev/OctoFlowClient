i#!/bin/bash

# Function to validate IPv4 address
validate_ip() {
    local ip=$1
    local IFS='.'
    local -a octets=($ip)
    
    # Check if we have exactly 4 octets
    if [ ${#octets[@]} -ne 4 ]; then
        return 1
    fi
    
    # Check each octet
    for octet in "${octets[@]}"; do
        # Check if octet is a number and within range 0-255
        if ! [[ "$octet" =~ ^[0-9]+$ ]] || [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
            return 1
        fi
        # Check for leading zeros (except for "0" itself)
        if [[ "$octet" =~ ^0[0-9] ]]; then
            return 1
        fi
    done
    
    return 0
}

# Function to configure loopback IP
configure_loopback() {
    local ip=$1

    # Add /32 if no CIDR notation is provided
    local ip_with_cidr
    if [[ "$ip" == */* ]]; then
        ip_with_cidr="$ip"
    else
        ip_with_cidr="$ip/32"
    fi
    
    # Check if the IP is already configured
    if ip addr show lo | grep -q "$ip"; then
        echo "The IP $ip is already configured on the loopback interface."
    else
        # Add the IP to the loopback interface
        sudo ip addr add "$ip_with_cidr" dev lo
        if [ $? -eq 0 ]; then
            echo "Successfully added $ip to the loopback interface."
        else
            echo "Failed to add $ip to the loopback interface. Please check your permissions."
        fi
    fi
}

# Function to configure ARP and rp_filter settings
configure_sysctl() {
    echo "Configuring sysctl settings for ARP and rp_filter..."
    if ! sudo sysctl -w net.ipv4.conf.all.arp_ignore=1 || \
       ! sudo sysctl -w net.ipv4.conf.all.arp_announce=2 || \
       ! sudo sysctl -w net.ipv4.conf.default.arp_ignore=1 || \
       ! sudo sysctl -w net.ipv4.conf.default.arp_announce=2 || \
       ! sudo sysctl -w net.ipv4.conf.all.rp_filter=0 || \
       ! sudo sysctl -w net.ipv4.conf.default.rp_filter=0; then
        echo "Failed to configure some sysctl settings. Please check your permissions."
        return 1
    fi

    # Persist settings to /etc/sysctl.d/99-keepalived.conf
    echo "Persisting sysctl settings to /etc/sysctl.d/99-keepalived.conf..."
    sudo bash -c 'cat > /etc/sysctl.d/99-keepalived.conf <<EOF
net.ipv4.ip_forward = 0
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
net.ipv4.conf.default.arp_ignore = 1
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
EOF'
    sudo sysctl --system
}

# Function to create a systemd service for VIP
create_systemd_service() {
    local ip=$1
    
    # Add /32 if no CIDR notation is provided
    local ip_with_cidr
    if [[ "$ip" == */* ]]; then
        ip_with_cidr="$ip"
    else
        ip_with_cidr="$ip/32"
    fi
    
    # Check if service already exists
    if systemctl list-unit-files add-vip.service >/dev/null 2>&1; then
        echo "Service add-vip.service already exists. Stopping and removing it first..."
        sudo systemctl stop add-vip.service 2>/dev/null || true
        sudo systemctl disable add-vip.service 2>/dev/null || true
    fi
    
    echo "Creating systemd service to manage VIP $ip..."
    sudo bash -c 'cat > /etc/systemd/system/add-vip.service <<EOF
[Unit]
Description=Add VIP to loopback
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "if ! ip addr show lo | grep -q '"$ip"'; then /sbin/ip addr add '"$ip_with_cidr"' dev lo; fi"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF'
    if ! sudo systemctl daemon-reload; then
        echo "Failed to reload systemd daemon."
        return 1
    fi
    
    if ! sudo systemctl enable add-vip.service; then
        echo "Failed to enable add-vip.service."
        return 1
    fi
    
    if ! sudo systemctl start add-vip.service; then
        echo "Warning: Failed to start add-vip.service, but the IP may already be configured."
        # Check if the IP is actually configured on the loopback interface
        if ip addr show lo | grep -q "$ip"; then
            echo "IP $ip is already configured on the loopback interface. Service creation completed."
        else
            echo "Failed to start add-vip.service and IP is not configured."
            return 1
        fi
    else
        echo "Successfully created and started add-vip.service."
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <loopback_ip>"
    echo "Example: $0 192.168.1.100"
    echo "Example: $0 192.168.1.100/32"
    echo ""
    echo "This script configures a loopback IP address with necessary system settings."
    exit 1
}

# Main script
# Check if IP address is provided as argument
if [ $# -eq 1 ]; then
    loopback_ip="$1"
    echo "Using loopback IP from argument: $loopback_ip"
elif [ $# -eq 0 ]; then
    # Interactive mode if no arguments provided
    read -p "Enter the loopback IP to configure (e.g., 192.168.1.100 or 192.168.1.100/32): " loopback_ip
else
    echo "Error: Too many arguments provided."
    show_usage
fi

# Extract IP part for validation (remove CIDR if present)
ip_part="${loopback_ip%/*}"

# Validate IP format
if validate_ip "$ip_part"; then
    echo "Configuring loopback IP: $loopback_ip"
    
    if configure_loopback "$loopback_ip" && configure_sysctl && create_systemd_service "$loopback_ip"; then
        echo "Successfully configured loopback IP $loopback_ip with all settings."
    else
        echo "Failed to complete the configuration. Please check the error messages above."
        exit 1
    fi
else
    echo "Invalid IP format. Please enter a valid IPv4 address (with optional /32 CIDR notation)."
    show_usage
fi
