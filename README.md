### OCI_Multi_VNIC_Setup
 Configure a Linux instance to use a secondary Vnic on OCI.

This script configures instance network settings for two VNICs on an OCI Oracle Linux, RedHat, CentOS, Alma Linux or Rocky Linux instance.
It is useful for network configuration on systems with multiple VNICs, ensuring specific routing and connectivity settings for each interface.
The primary and the secondary Vnics can be attached to the same subnet or not (public/private subnets)

## Quick Start
```
curl -o OCI_Multi_VNIC_Setup.sh https://raw.githubusercontent.com/Olygo/OCI_Multi_VNIC_Setup/refs/heads/main/OCI_Multi_VNIC_Setup.sh
chmod +x ./OCI_Multi_VNIC_Setup.sh
sudo ./OCI_Multi_VNIC_Setup.sh
```

## What This Script Does:
    Configures secondary Vnic with NetworkManager.
    Enables IP forwarding and sets up reverse path filtering.
    Adds custom routing tables and IP rules.
    Creates a script to reapply routing configurations on reboot.
    Sets up a systemd service to execute the persistence script automatically on boot.
    Verifies connectivity to both VNICs after configuration.

## Compatibility
    **Oracle Linux**: Fully compatible from 7.x to 9.x
    **RHEL/CentOS*: This script works from 7.x to 9.x
    **AlmaLinux/Rocky Linux**: Fully compatible from 7.x to 9.x.

    For older versions (< 7.X), modifications would be needed since nmcli is unavailable.

    **Ubuntu**: The script will need significant changes, as Ubuntu uses netplan (or older /etc/network/interfaces) instead of nmcli. 
    Adjustments for netplan would be necessary.

## User Input Prompts: 
    A helper function prompt() asks for:
    - The primary VNIC's private IP address (e.g. 10.0.100.10)
    - The secondary Vnic/interface name (e.g. eth1)
    - The secondary VNIC's private IP address ** IN CIDR NOTATION ** (e.g. 10.0.100.20/24)
    - The MAC address for the secondary VNIC (e.g. 00:01:23:45:67:89)
    - The gateway IP address of the subnet (e.g. 10.0.100.1)

## Logging and Error Handling: 
    The script enables verbose mode with set -e (exit on error) and set -o pipefail (fail on pipeline errors). 
    It logs output to /var/log/configure_eth.log.

## Questions and Feedbacks ?
**_olygo.git@gmail.com_**

## Disclaimer
**Always ensure thorough testing of any script on test resources prior to deployment in a production environment to avoid potential outages or unexpected costs. 
This script does not interact with or create any resources in your environment.**

**This script is an independent tool developed by Florian Bonneville and is not affiliated with or supported by Oracle. 
It is provided as-is and without any warranty or official endorsement from Oracle**
