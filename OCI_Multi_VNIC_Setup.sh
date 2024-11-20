#!/bin/bash

# =========================================================================================================
# Name            : OCI_Multi_VNIC_Setup.sh
# Date            : 21 November 2024
# Autor           : Florian Bonneville
# Version         : 1.0.0
#
# Usage           : chmod +x ./OCI_Multi_VNIC_Setup.sh && sudo ./OCI_Multi_VNIC_Setup.sh
#
# Logs            : /var/log/configure_eth.log
#
# =========================================================================================================

clear

echo -e "\n=================================================================="
echo -e "*"
echo -e "*    - Configures a secondary VNIC in one of two scenarios:"
echo -e "*        1. Same subnet as the primary VNIC (no separate gateway)"
echo -e "*        2. Different subnet with its own gateway"
echo -e "*"
echo -e "*    - Ensures configurations persist across reboots"
echo -e "*"
echo -e "==================================================================\n"

# Check if the script is being run as root or with sudo
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\nThis script must be run as root or with sudo. Exiting.\n"
    exit 1
fi

# Enable verbose mode
set -e
set -o pipefail

# Set log file
LOGFILE="/var/log/configure_eth.log"
exec > >(tee -a "$LOGFILE") 2>&1

# Fetch Vnic's properties
vnics_name=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "^lo" | xargs)
vnics_ips_masks=$(ip -o -4 addr show | awk '{print $4}' | grep -v "^127\." | xargs)
vnics_ips=$(ip -o -4 addr show | awk '{print $4}' | grep -v "^127\." | cut -d'/' -f1 | xargs)
ip_01=$(echo "$vnics_ips" | awk '{print $1}')
ip_gw=$(echo "$ip_01" | sed 's/\.[0-9]*$/\.1/')

# ==============================
# Functions
# ==============================

# Function to prompt for user input
prompt() {
  local var_name=$1
  local prompt_message=$2
  local input

  while [[ -z $input ]]; do
    read -rp "$prompt_message: " input
    if [[ -z $input ]]; then
      echo "Error: Input cannot be empty. Please try again."
    fi
  done

  export "$var_name"="$input"
}

# Set Network properties from user prompt
set_network_configuration(){ 
    # Prompt user for configuration variables
    echo -e "\nEnter primary VNIC's interface name (e.g., $vnics_name):"
    prompt ETH_IFACE_1 "Primary VNIC Interface Name"

    echo -e "\nEnter primary VNIC's private IP address (e.g., $vnics_ips):"
    prompt ETH_IFACE_1_IP "Primary VNIC IP"

    echo -e "\nEnter primary VNIC's Gateway IP address (e.g., $ip_gw):"
    prompt ETH_IFACE_1_GW "Gateway IP"

    echo -e "\nEnter secondary VNIC's interface name (e.g., $vnics_name):"
    prompt ETH_IFACE_2 "Secondary VNIC Interface Name"

    echo -e "\nEnter secondary VNIC's private IP address (e.g., $vnics_ips_masks):"
    prompt ETH_IFACE_2_IP "Secondary VNIC IP Address (CIDR Notation)"

    echo -e "\nEnter secondary VNIC's MAC address (e.g., 00:01:23:45:67:89):"
    prompt ETH_IFACE_2_MAC "Secondary VNIC MAC Address"

    echo -e "\nIs the secondary VNIC in a different subnet (y/n)?"
    read -rp "Your choice: " DIFF_SUBNET

    if [[ "$DIFF_SUBNET" =~ ^[Yy]$ ]]; then
        ip_gw2=$(echo "$ETH_IFACE_2_IP" | cut -d'/' -f1 | sed 's/\.[0-9]*$/\.1/')
        echo -e "\nEnter the gateway for the secondary VNIC subnet (e.g., $ip_gw2):"
        prompt ETH_IFACE_2_GW "Secondary VNIC Gateway"
    else
        ETH_IFACE_2_GW=""
    fi

    confirm_configuration
}

confirm_configuration() {
    clear
    echo -e "\n\nSummary of your configuration:"
    echo -e "   - The primary Vnic name is:            $ETH_IFACE_1"
    echo -e "   - The primary Vnic IP is:              $ETH_IFACE_1_IP"
    echo -e "   - The primary Vnic GW is:              $ETH_IFACE_1_GW"
    echo -e "   - The secondary Vnic name is:          $ETH_IFACE_2"
    echo -e "   - The secondary Vnic IP with CIDR is:  $ETH_IFACE_2_IP"
    echo -e "   - The secondary Vnic MAC is:           $ETH_IFACE_2_MAC"

    if [[ "$DIFF_SUBNET" =~ ^[Yy]$ ]]; then
        echo -e "   - The secondary Vnic GW is:            $ETH_IFACE_2_GW"
    else
        echo -e "   - The secondary Vnic GW is:            $ETH_IFACE_1_GW"    
    fi

    echo
    read -rp "Do you confirm these settings ? (y)es/(n)o/(q)uit: " CONFIRM_SETTINGS

    if [[ "$CONFIRM_SETTINGS" =~ ^[Qq]$ ]]; then
        exit
    elif [[ ! "$CONFIRM_SETTINGS" =~ ^[Yy]$ ]]; then
        clear
        set_network_configuration
    else
        echo -e "\nUser settings confirmed..."
    fi
}

# Function to check if a package is installed
check_and_install() {
    local package=$1
    if ! rpm -q "$package" &>/dev/null; then
        echo "Package '$package' is not installed. Installing it now..."
        yum install -y "$package" || { echo "Failed to install $package. Exiting."; exit 1; }
        echo "Package '$package' successfully installed."
    else
        echo "Package '$package' is already installed. Proceeding."
    fi
}

# Function to check ip route configuration
configure_ip_route() {
    if [ ! -d /etc/iproute2 ]; then
        echo "Directory '/etc/iproute2' does not exist. Creating it..."
        mkdir -p /etc/iproute2 || { echo "Failed to create directory '/etc/iproute2'. Exiting."; exit 1; }
        echo "Directory '/etc/iproute2' created successfully."
    else
        echo "Directory '/etc/iproute2' already exists. Proceeding."
    fi

    # Ensure /etc/iproute2/rt_tables file exists
    echo -e "\n *** Ensure /etc/iproute2/rt_tables file exists *** "

    if [ ! -f /etc/iproute2/rt_tables ]; then
        echo "File '/etc/iproute2/rt_tables' does not exist. Creating it..."
        touch /etc/iproute2/rt_tables || { echo "Failed to create file '/etc/iproute2/rt_tables'. Exiting."; exit 1; }
        echo "# Reserved routing table identifiers" > /etc/iproute2/rt_tables
        echo "File '/etc/iproute2/rt_tables' created successfully with a default header."
    else
        echo "File '/etc/iproute2/rt_tables' already exists. Proceeding."
    fi
}

# Function to check and install NetworkManager
check_and_install_nmcli() {
    if ! command -v nmcli &>/dev/null; then
        echo "nmcli not found. Installing NetworkManager..."
        
        # Determine the package manager and install NetworkManager
        if command -v yum &>/dev/null; then
            yum install -y NetworkManager
        elif command -v dnf &>/dev/null; then
            dnf install -y NetworkManager
        else
            echo "Error: Could not determine package manager. Exiting."
            exit 1
        fi

        echo -e "\nNetworkManager installed successfully."
    else
        echo -e "\nnmcli is already installed."
    fi
}

# Function to enable and start NetworkManager
configure_and_start_nmcli() {
    if systemctl is-enabled NetworkManager &>/dev/null; then
        echo "NetworkManager is already enabled."
    else
        echo "Enabling NetworkManager..."
        systemctl unmask NetworkManager
        systemctl enable NetworkManager
    fi

    if systemctl is-active NetworkManager &>/dev/null; then
        echo "NetworkManager is already running."
    else
        echo "Starting NetworkManager..."
        systemctl start NetworkManager
    fi
    echo "NetworkManager is configured and running."
}

# ==============================
# Main
# ==============================

set_network_configuration
confirm_configuration

echo -e "\n *** Checking if NetworkManager CLI (nmcli) is installed ***"
check_and_install_nmcli

echo -e "\n *** Configuring NetworkManager ***"
configure_and_start_nmcli

echo -e "\n *** Check and install iproute if not installed *** "
check_and_install "iproute"

echo -e "\n *** Ensure /etc/iproute2 directory exists *** "
configure_ip_route

echo -e "\n *** Starting $ETH_IFACE_2 configuration and persistence setup ***"

# Configure secondary VNIC with NetworkManager
echo -e "\n *** Configure secondary VNIC with NetworkManager ***"

nmcli con add type ethernet con-name "$ETH_IFACE_2" ifname "$ETH_IFACE_2" mac "$ETH_IFACE_2_MAC"
nmcli con modify "$ETH_IFACE_2" ipv4.addresses "$ETH_IFACE_2_IP"
nmcli con modify "$ETH_IFACE_2" ipv4.gateway "$ETH_IFACE_2_GW"  # Set gateway if provided
nmcli con modify "$ETH_IFACE_2" ipv4.method manual
nmcli con modify "$ETH_IFACE_2" connection.autoconnect yes
nmcli con modify "$ETH_IFACE_2" 802-3-ethernet.mtu 9000
nmcli con up "$ETH_IFACE_2"

# Enable IP forwarding and configure reverse path filtering
echo -e "\n *** Enable IP forwarding and configure reverse path filtering ***"

cat <<EOF | tee -a /etc/sysctl.conf
# Enable IP forwarding
net.ipv4.ip_forward=1

# Configure reverse path filtering
net.ipv4.conf.all.rp_filter=2
net.ipv4.conf.default.rp_filter=2
net.ipv4.conf.$ETH_IFACE_1.rp_filter=2
net.ipv4.conf.$ETH_IFACE_2.rp_filter=2
EOF

# Apply sysctl settings immediately
echo -e "\n *** Apply sysctl settings immediately ***"
sysctl -p

# Add routing tables and IP rules
echo -e "\n *** Adding custom routing tables *** "
grep -q "vnic_1" /etc/iproute2/rt_tables || echo "100 vnic_1" | tee -a /etc/iproute2/rt_tables
grep -q "vnic_2" /etc/iproute2/rt_tables || echo "200 vnic_2" | tee -a /etc/iproute2/rt_tables

echo -e "\n *** Adding IP rules and routes *** "
ip rule add from $ETH_IFACE_1_IP table vnic_1
ip rule add from ${ETH_IFACE_2_IP%/*} table vnic_2

# Primary VNIC routing
ip route add default via "$ETH_IFACE_1_GW" dev $ETH_IFACE_1 table vnic_1

# Secondary VNIC routing with conditional gateway
if [[ -n "$ETH_IFACE_2_GW" ]]; then
    ip route add default via "$ETH_IFACE_2_GW" dev "$ETH_IFACE_2" table vnic_2
else
    ip route add default via "$ETH_IFACE_1_GW" dev "$ETH_IFACE_2" table vnic_2
fi

# Create a script to reapply routing rules after reboot
echo -e "\n *** Creating policy routing persistence script *** "

tee /usr/local/bin/setup_policy_routing.sh > /dev/null <<EOF
#!/bin/bash

# Reapply IP rules
ip rule add from $ETH_IFACE_1_IP table vnic_1
ip rule add from ${ETH_IFACE_2_IP%/*} table vnic_2

# Reapply routing rules
ip route add default via $ETH_IFACE_1_GW dev $ETH_IFACE_1 table vnic_1
EOF

if [[ -n "$ETH_IFACE_2_GW" ]]; then
    echo "ip route add default via $ETH_IFACE_2_GW dev $ETH_IFACE_2 table vnic_2" >> /usr/local/bin/setup_policy_routing.sh
else
    echo "ip route add default via $ETH_IFACE_1_GW dev $ETH_IFACE_2 table vnic_2" >> /usr/local/bin/setup_policy_routing.sh
fi

chmod +x /usr/local/bin/setup_policy_routing.sh

# Create a systemd service to run the script on boot
echo -e "\n *** Creating systemd service for policy routing *** "

tee /etc/systemd/system/policy-routing.service > /dev/null <<EOF
[Unit]
Description=Setup Policy Routing for Multiple VNICs
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup_policy_routing.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

systemctl enable policy-routing.service

# Test connectivity
echo -e "\n *** Testing connectivity *** "
ping -c 4 "$ETH_IFACE_1_IP"
ping -c 4 "${ETH_IFACE_2_IP%/*}"
ping -c 4 "$ETH_IFACE_1_GW"

# Summary of configuration
echo -e "\n *** Network configuration completed *** "
echo -e "\nIP rules:"
ip rule show
echo -e "\n$ nmcli device show $ETH_IFACE_2\n"
nmcli device show $ETH_IFACE_2

echo -e "\n *** Configuration complete! $ETH_IFACE_2 is set up and all settings are persistent *** \n"
exit 0
