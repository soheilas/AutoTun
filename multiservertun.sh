#!/bin/bash

# Colors for messages
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

# Function to display progress messages step-by-step
echo_step_done() {
  clear
  echo -e "${GREEN}${BOLD}$1 : DONE${RESET}"
  sleep 2
}

# Display initial message
clear
echo -e "${BOLD}Starting Multi-Tunnel Setup...${RESET}"
sleep 1

# Install necessary packages (only once)
echo -e "Installing necessary packages..."
apt update && apt install -y sshpass iproute2 haproxy
if [ $? -ne 0 ]; then
  echo -e "${RED}${BOLD}Error installing packages! Please check.${RESET}"
  exit 1
fi
echo_step_done "Installing necessary packages"

# Ensure rc.local exists and is executable (only once)
if [ ! -f /etc/rc.local ]; then
  echo -e "${BOLD}Creating /etc/rc.local...${RESET}"
  cat <<EOF > /etc/rc.local
#!/bin/bash
# rc.local file for custom startup commands
exit 0
EOF
  if [ $? -eq 0 ]; then
    echo_step_done "Created /etc/rc.local"
  else
    echo -e "${RED}${BOLD}Failed to create /etc/rc.local${RESET}"
    exit 1
  fi
fi

chmod +x /etc/rc.local
systemctl enable rc-local.service
systemctl start rc-local.service
echo_step_done "rc-local service configured"

# Automatically find the IP address of this server (Iran server)
IPIRAN=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
echo -e "Detected Iran server IP: ${BOLD}$IPIRAN${RESET}"
echo_step_done "Detected local server IP"

# Get number of tunnels to create
read -p "How many tunnels do you want to create? " NUM_TUNNELS

# Initialize HAProxy config if not exists
HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"
if [ ! -f "${HAPROXY_CONFIG}.backup" ]; then
  cp $HAPROXY_CONFIG "${HAPROXY_CONFIG}.backup"
fi

# Arrays to store tunnel information
declare -a TUNNEL_NAMES
declare -a KHAREJ_IPS
declare -a PASSWORDS

# Collect information for all tunnels
for ((i=1; i<=NUM_TUNNELS; i++)); do
  echo -e "\n${BOLD}=== Tunnel $i Configuration ===${RESET}"
  
  read -p "Enter tunnel name for tunnel $i (e.g., DE$i): " TUNNEL_NAME
  read -p "Enter kharej server IP for tunnel $i: " IPKHAJ
  read -sp "Enter password for kharej server $i: " root_password
  echo
  
  TUNNEL_NAMES[$i]=$TUNNEL_NAME
  KHAREJ_IPS[$i]=$IPKHAJ
  PASSWORDS[$i]=$root_password
  
  echo_step_done "Collected info for tunnel $i"
done

# Create tunnels
for ((i=1; i<=NUM_TUNNELS; i++)); do
  TUNNEL_NAME=${TUNNEL_NAMES[$i]}
  IPKHAJ=${KHAREJ_IPS[$i]}
  root_password=${PASSWORDS[$i]}
  
  echo -e "\n${BOLD}=== Setting up Tunnel $i: $TUNNEL_NAME ===${RESET}"
  
  # Calculate unique IPv6 and IPv4 ranges for each tunnel
  IPV6_SUBNET="fd60:e9e:818$i"
  IPV4_RANGE="172.28.$i"
  PRIVATE_RANGE="192.168.$((30+i))"
  IPV6_RANGE="2001:0db8:85a3:08d3:1319:8a2e:031$i"
  
  # Create script for Iran server
  cat > "${TUNNEL_NAME}_iran.sh" <<EOF
#!/bin/bash

ip tunnel add 6to4_To_${TUNNEL_NAME} mode sit remote $IPKHAJ local $IPIRAN
ip -6 addr add ${IPV6_SUBNET}::1/64 dev 6to4_To_${TUNNEL_NAME}
ip link set 6to4_To_${TUNNEL_NAME} mtu 1480
ip link set 6to4_To_${TUNNEL_NAME} up
ip -6 tunnel add GRE6Tun_To_${TUNNEL_NAME} mode ip6gre remote ${IPV6_SUBNET}::2 local ${IPV6_SUBNET}::1
ip addr add ${IPV4_RANGE}.1/30 dev GRE6Tun_To_${TUNNEL_NAME}
ip addr add ${PRIVATE_RANGE}.1/24 dev GRE6Tun_To_${TUNNEL_NAME}
ip -6 addr add ${IPV6_RANGE}:1/64 dev GRE6Tun_To_${TUNNEL_NAME}
ip link set GRE6Tun_To_${TUNNEL_NAME} mtu 1436
ip link set GRE6Tun_To_${TUNNEL_NAME} up

exit 0
EOF

  chmod +x "${TUNNEL_NAME}_iran.sh"
  echo_step_done "Created iran server script for $TUNNEL_NAME"

  # Execute the Iran script locally
  ./"${TUNNEL_NAME}_iran.sh"
  if [ $? -eq 0 ]; then
    echo_step_done "Executed iran server script for $TUNNEL_NAME"
  else
    echo -e "${RED}${BOLD}Error executing local server script for $TUNNEL_NAME!${RESET}"
    continue
  fi

  # Add commands to rc.local for persistence
  cat <<EOR >> /etc/rc.local

# Tunnel setup for ${TUNNEL_NAME}
ip tunnel add 6to4_To_${TUNNEL_NAME} mode sit remote $IPKHAJ local $IPIRAN
ip -6 addr add ${IPV6_SUBNET}::1/64 dev 6to4_To_${TUNNEL_NAME}
ip link set 6to4_To_${TUNNEL_NAME} mtu 1480
ip link set 6to4_To_${TUNNEL_NAME} up
ip -6 tunnel add GRE6Tun_To_${TUNNEL_NAME} mode ip6gre remote ${IPV6_SUBNET}::2 local ${IPV6_SUBNET}::1
ip addr add ${IPV4_RANGE}.1/30 dev GRE6Tun_To_${TUNNEL_NAME}
ip addr add ${PRIVATE_RANGE}.1/24 dev GRE6Tun_To_${TUNNEL_NAME}
ip -6 addr add ${IPV6_RANGE}:1/64 dev GRE6Tun_To_${TUNNEL_NAME}
ip link set GRE6Tun_To_${TUNNEL_NAME} mtu 1436
ip link set GRE6Tun_To_${TUNNEL_NAME} up
EOR
  echo_step_done "Updated rc.local for iran server - $TUNNEL_NAME"

  # Create and execute the script for the foreign server using sshpass
  sshpass -p "$root_password" ssh -o StrictHostKeyChecking=no root@$IPKHAJ "bash -s" <<EOF
ip tunnel add 6to4_To_${TUNNEL_NAME} mode sit remote $IPIRAN local $IPKHAJ
ip -6 addr add ${IPV6_SUBNET}::2/64 dev 6to4_To_${TUNNEL_NAME}
ip link set 6to4_To_${TUNNEL_NAME} mtu 1480
ip link set 6to4_To_${TUNNEL_NAME} up
ip -6 tunnel add GRE6Tun_To_${TUNNEL_NAME} mode ip6gre remote ${IPV6_SUBNET}::1 local ${IPV6_SUBNET}::2
ip addr add ${IPV4_RANGE}.2/30 dev GRE6Tun_To_${TUNNEL_NAME}
ip addr add ${PRIVATE_RANGE}.2/24 dev GRE6Tun_To_${TUNNEL_NAME}
ip -6 addr add ${IPV6_RANGE}:2/64 dev GRE6Tun_To_${TUNNEL_NAME}
ip link set GRE6Tun_To_${TUNNEL_NAME} mtu 1436
ip link set GRE6Tun_To_${TUNNEL_NAME} up

# Add to rc.local for persistence
cat <<EOR >> /etc/rc.local

# Tunnel setup for ${TUNNEL_NAME}
ip tunnel add 6to4_To_${TUNNEL_NAME} mode sit remote $IPIRAN local $IPKHAJ
ip -6 addr add ${IPV6_SUBNET}::2/64 dev 6to4_To_${TUNNEL_NAME}
ip link set 6to4_To_${TUNNEL_NAME} mtu 1480
ip link set 6to4_To_${TUNNEL_NAME} up
ip -6 tunnel add GRE6Tun_To_${TUNNEL_NAME} mode ip6gre remote ${IPV6_SUBNET}::1 local ${IPV6_SUBNET}::2
ip addr add ${IPV4_RANGE}.2/30 dev GRE6Tun_To_${TUNNEL_NAME}
ip addr add ${PRIVATE_RANGE}.2/24 dev GRE6Tun_To_${TUNNEL_NAME}
ip -6 addr add ${IPV6_RANGE}:2/64 dev GRE6Tun_To_${TUNNEL_NAME}
ip link set GRE6Tun_To_${TUNNEL_NAME} mtu 1436
ip link set GRE6Tun_To_${TUNNEL_NAME} up
EOR
EOF

  if [ $? -eq 0 ]; then
    echo_step_done "Executed kharej server script and updated rc.local for $TUNNEL_NAME"
  else
    echo -e "${RED}${BOLD}Error executing kharej server script for $TUNNEL_NAME!${RESET}"
    continue
  fi

  # Ping to verify the tunnel setup
  echo -e "Pinging tunnel IPs to verify $TUNNEL_NAME..."
  ping -c 2 ${IPV4_RANGE}.2
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}${BOLD}Ping to $TUNNEL_NAME tunnel IP successful!${RESET}"
  else
    echo -e "${RED}${BOLD}Ping to $TUNNEL_NAME tunnel IP failed! Please check the setup.${RESET}"
  fi

  # Get VPN ports for this tunnel
  read -p "Enter VPN ports for $TUNNEL_NAME separated by dash (e.g., 443-1080-1995): " PORTS_INPUT

  # Convert dash-separated list to array
  IFS='-' read -ra PORT_ARRAY <<< "$PORTS_INPUT"

  echo -e "Updating HAProxy configuration for $TUNNEL_NAME..."

  for PORT in "${PORT_ARRAY[@]}"; do
  cat <<EOL >> $HAPROXY_CONFIG


frontend ${TUNNEL_NAME}_${PORT}
    bind :::${PORT}
    mode tcp
    option tcplog
    default_backend ${TUNNEL_NAME}_${PORT}

backend ${TUNNEL_NAME}_${PORT}
    mode tcp
    balance roundrobin
    server tunnel ${IPV4_RANGE}.2:${PORT}

EOL
  done

  echo_step_done "Updated HAProxy configuration for $TUNNEL_NAME"
done

# Restart HAProxy service
systemctl restart haproxy
if [ $? -eq 0 ]; then
  echo -e "${GREEN}${BOLD}HAProxy restarted successfully!${RESET}"
else
  echo -e "${RED}${BOLD}Error restarting HAProxy!${RESET}"
  exit 1
fi

# Final success message
echo -e "${GREEN}${BOLD}Multi-Tunnel setup completed successfully!${RESET}"
echo -e "${GREEN}${BOLD}Created $NUM_TUNNELS tunnels with the following names:${RESET}"
for ((i=1; i<=NUM_TUNNELS; i++)); do
  echo -e "${GREEN}- ${TUNNEL_NAMES[$i]}${RESET}"
done
