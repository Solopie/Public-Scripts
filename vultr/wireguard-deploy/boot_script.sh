#!/bin/bash

# Redacted variables that should be set in the environment:
# LOCAL_USERNAME=<REDACTED>
# PEER_PUBLIC_KEY=<REDACTED>
# VULTR_API_KEY=<REDACTED>

# This script should be run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

apt-get update && sudo apt-get upgrade -y
sudo apt-get install wireguard -y

echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

# Enable wireguard port on firewall
ufw allow 51820/udp

# Generate server keys
mkdir -p /etc/wireguard/server_keys
umask 077
wg genkey | tee /etc/wireguard/server_keys/privatekey | wg pubkey > /etc/wireguard/server_keys/publickey

# Generate client keys
mkdir -p /etc/wireguard/client_keys
wg genkey | tee /etc/wireguard/client_keys/privatekey_p1 | wg pubkey > /etc/wireguard/client_keys/publickey_p1

# Generate wireguard server config
SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_keys/privatekey)
CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/client_keys/publickey_p1)
DEFAULT_NETWORK_INTERFACE=$(ip route | grep default | awk '{print $5}')
WG_SERVER_CONFIG_FILE="wg0.conf"

# Write the configuration to the file
cat > "/etc/wireguard/$WG_SERVER_CONFIG_FILE" << EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = 10.0.0.1/24
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $DEFAULT_NETWORK_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $DEFAULT_NETWORK_INTERFACE -j MASQUERADE
ListenPort = 51820

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = 10.0.0.2/32
EOF

wg-quick up wg0
systemctl enable wg-quick@wg0

# Generate wireguard client config
CLIENT_PRIVATE_KEY=$(cat /etc/wireguard/client_keys/privatekey_p1)
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_keys/publickey)
SERVER_PUBLIC_IP=$(curl --silent -4 ifconfig.me)
WG_CLIENT_CONFIG_FILE="wg0-client.conf"

cat > "/etc/wireguard/$WG_CLIENT_CONFIG_FILE" << EOF
[Interface]
Address = 10.0.0.2/32
PrivateKey = $CLIENT_PRIVATE_KEY
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_PUBLIC_IP:51820
AllowedIPs = 0.0.0.0/0, ::/0
EOF

# Move VPN config file into local user folder
adduser --system --comment "VPN Key Retrieval" --home /home/$LOCAL_USERNAME --shell /bin/bash $LOCAL_USERNAME
cp /etc/wireguard/$WG_CLIENT_CONFIG_FILE /home/$LOCAL_USERNAME/
chown $LOCAL_USERNAME /home/$LOCAL_USERNAME/$WG_CLIENT_CONFIG_FILE

# Write public key to local user for remote pulling of the wireguard client configuration
mkdir -p /home/$LOCAL_USERNAME/.ssh/
echo "$PEER_PUBLIC_KEY" >> /home/$LOCAL_USERNAME/.ssh/authorized_keys
chown -R $LOCAL_USERNAME /home/$LOCAL_USERNAME/.ssh/

# Write auto-destruction services
wget -O /usr/local/bin/check_time_and_destroy.sh https://raw.githubusercontent.com/Solopie/Public-Scripts/refs/heads/main/vultr/wireguard-deploy/check_time_and_destroy.sh
chmod +x /usr/local/bin/check_time_and_destroy.sh
wget -O /etc/systemd/system/check_time_and_destroy.service https://raw.githubusercontent.com/Solopie/Public-Scripts/refs/heads/main/vultr/wireguard-deploy/check_time_and_destroy.service
sed -i "s|<VULTR_API_KEY>|$VULTR_API_KEY|g" /etc/systemd/system/check_time_and_destroy.service
sed -i "s|<LOCAL_USERNAME>|$LOCAL_USERNAME|g" /etc/systemd/system/check_time_and_destroy.service
wget -O /etc/systemd/system/check_time_and_destroy.timer https://raw.githubusercontent.com/Solopie/Public-Scripts/refs/heads/main/vultr/wireguard-deploy/check_time_and_destroy.timer
systemctl daemon-reload
systemctl start check_time_and_destroy.timer

