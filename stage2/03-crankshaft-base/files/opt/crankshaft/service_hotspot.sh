#!/bin/bash +e

source /opt/crankshaft/crankshaft_default_env.sh
source /opt/crankshaft/crankshaft_system_env.sh

if [ $ENABLE_HOTSPOT -eq 1 ]; then
    if [ $1 == "start" ]; then
        crankshaft filesystem system unlock
        # cleanup possible lost state file
        sudo rm -f /tmp/hotspot_active > /dev/null 2>$1
        log_echo "Kill running wpa clients"
        echo "[${CYAN}${BOLD} INFO ${RESET}] Exit/kill wpa_supplicant (wifi client mode)"
        # exit possible running wpa client sessions
        wpa_cli terminate > /dev/null 2>$1
        killall wpa_supplicant > /dev/null 2>$1
        # switch of down to re setup
        log_echo "Switch off wlan0"
        echo "[${CYAN}${BOLD} INFO ${RESET}] Switch wifi off"
        ifconfig wlan0 down
        # configure interface
        log_echo "Configure ip for wlan0"
        echo "[${CYAN}${BOLD} INFO ${RESET}] Configure interface ip"
        # 5 client ip's available (sum 6)
        ifconfig wlan0 192.168.254.1 netmask 255.255.255.248 broadcast 192.168.254.7
        #switch power management
        log_echo "Switch on wlan0"
        echo "[${CYAN}${BOLD} INFO ${RESET}] Switch wifi on"
        iwconfig wlan0 power on
        # delete existing rules
        log_echo "Delete iptables"
        echo "[${CYAN}${BOLD} INFO ${RESET}] Deleting iptable rules"
        /sbin/iptables -F
        /sbin/iptables -X
        /sbin/iptables -t nat -F
        # allow lookup
        log_echo "Setup iptables"
        echo "[${CYAN}${BOLD} INFO ${RESET}] Setup iptables for rounting"
        /sbin/iptables -A INPUT -i lo -j ACCEPT
        /sbin/iptables -A OUTPUT -o lo -j ACCEPT
        # enable nat and Masq
        /sbin/iptables -A FORWARD -o eth0 -i wlan0 -m conntrack --ctstate NEW -j ACCEPT
        /sbin/iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        /sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
        # ip forwarding
        log_echo "Allow forwarding"
        echo "[${CYAN}${BOLD} INFO ${RESET}] Allow forwarding"
        sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>$1
        # set wpa password
        log_echo "Set wpa credentials"
        echo "[${CYAN}${BOLD} INFO ${RESET}] Setup hotspod credentials from config"
        sed -i 's/^wpa_passphrase=.*$/wpa_passphrase='"${HOTSPOT_PSK}"'/' /etc/hostapd/hostapd.conf
        sed -i 's/^country_code=.*$/country_code='"${WIFI_COUNTRY}"'/' /etc/hostapd/hostapd.conf
        # start services
        echo "[${CYAN}${BOLD} INFO ${RESET}] Start dnsmasq"
        systemctl start dnsmasq
        echo "[${CYAN}${BOLD} INFO ${RESET}] Start hostapd"
        systemctl start hostapd
        HOSTAPD=`systemctl status hostapd | grep running | awk {'print $3'} | cut -d'(' -f2 | cut -d')' -f1`
        if [ "$HOSTAPD" != "running" ]; then
            echo "[${RED}${BOLD} FAIL ${RESET}] Hostapd has failed to start!"
        fi
        DNSMASQ=`systemctl status hostapd | grep running | awk {'print $3'} | cut -d'(' -f2 | cut -d')' -f1`
        if [ "$DNSMASQ" != "running" ]; then
            echo "[${RED}${BOLD} FAIL ${RESET}] Dnsmasq has failed to start!"
        fi
        if [ "$HOSTAPD" == "running" ] && [ "$DNSMASQ" == "running" ]; then
        touch /tmp/hotspot_active > /dev/null 2>$1
        fi
        crankshaft filesystem system lock
        # show infos
        _SSID_WLAN0=$(cat /etc/hostapd/hostapd.conf | grep '^ssid' | cut -d= -f2)
        _PSK_WLAN0=$(cat /etc/hostapd/hostapd.conf | grep '^wpa_passphrase' | cut -d= -f2)
        _ENC_WLAN0=$(cat /etc/hostapd/hostapd.conf | grep '^wpa=' | cut -d= -f2)
        _IP_WLAN0=$(ifconfig wlan0 | grep 'inet ' | awk '{print $2}')
        echo "[${CYAN}${BOLD} INFO ${RESET}] ${BLUE}${BOLD}${GREEN}wlan0: ${RESET}Mode       ${CYAN}Hotspot${RESET}"
        echo "[${CYAN}${BOLD} INFO ${RESET}] ${BLUE}${BOLD}${GREEN}wlan0: ${RESET}IP         ${MAGENTA}$_IP_WLAN0${RESET}"
        echo "[${CYAN}${BOLD} INFO ${RESET}] ${BLUE}${BOLD}${GREEN}wlan0: ${RESET}SSID       ${YELLOW}$_SSID_WLAN0${RESET}"
        echo "[${CYAN}${BOLD} INFO ${RESET}] ${BLUE}${BOLD}${GREEN}wlan0: ${RESET}PSK        ${YELLOW}$_PSK_WLAN0${RESET}"
        echo "[${CYAN}${BOLD} INFO ${RESET}] ${BLUE}${BOLD}${GREEN}wlan0: ${RESET}Type       ${YELLOW}WPA$_ENC_WLAN0${RESET}"
        exit 0
    fi

    if [ $1 == "stop" ]; then
        crankshaft filesystem system unlock
        # clanup state file
        sudo rm -f /tmp/hotspot_active > /dev/null 2>$1
        log_echo "Stop hotspot"
        # stop hostapd and dnsmasq dhcp server
        log_echo "Stop hostapd"
        echo "[${CYAN}${BOLD} INFO ${RESET}] Stopping hostapd"
        systemctl stop hostapd
        log_echo "Stop dnsmasq"
        echo "[${CYAN}${BOLD} INFO ${RESET}] Stopping dnsmasq"
        systemctl stop dnsmasq
        # delete existing rules
        log_echo "Delete iptables"
        echo "[${CYAN}${BOLD} INFO ${RESET}] Deleting iptable rules"
        /sbin/iptables -F
        /sbin/iptables -X
        /sbin/iptables -t nat -F
        #switch power management
        log_echo "Switch on wlan0"
        iwconfig wlan0 power on
        log_echo "Bring wlan0 up"
        echo "[${CYAN}${BOLD} INFO ${RESET}] Bring up wlan0 interface"
        ifconfig wlan0 up
        # configure blank interface
        echo "[${CYAN}${BOLD} INFO ${RESET}] Reconfigure ip wlan0"
        log_echo "Cleanup ip address for wlan0"
        ip address del 192.168.254.1/29 dev wlan0
        # start wpa client only if not in dev or debug mode
        if [ -f /tmp/usb_debug_mode ] || [ -f /tmp/dev_mode_enabled ]; then
            # start wpa_supplicant
            echo "[${CYAN}${BOLD} INFO ${RESET}] Start wpa_supplicant (client mode)"
            log_echo "Cleanup ip address for wlan0"
            sudo wpa_supplicant -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -B > /dev/null 2>$1
            crankshaft filesystem system lock
            echo "[${CYAN}${BOLD} INFO ${RESET}] Waiting for ip release..."
            log_echo "Waitin for ip release"
            # check 15 secs for valid ip config
            counter=0
            while [ $counter -lt 15 ]; do
                # Get ip addresses by interface
                if [ -d /sys/class/net/wlan0 ]; then
                    _IP_WLAN0=$(ifconfig wlan0 | grep 'inet ' | awk '{print $2}')
                    if [ "$_IP_WLAN0" ]; then
                        break
                    fi
                fi
                counter=$((counter+1))
                sleep 1
            done
            _SSID_WLAN0=$(wpa_cli -i wlan0 status | grep '^ssid' | cut -d= -f2)
            _FREQ_WLAN0=$(wpa_cli -i wlan0 status | grep '^freq' | cut -d= -f2)
            _ENC_WLAN0=$(wpa_cli -i wlan0 status | grep '^key_mgmt' | cut -d= -f2)
            echo "[${CYAN}${BOLD} INFO ${RESET}] ${BLUE}${BOLD}${GREEN}wlan0: ${RESET}Mode       ${CYAN}Client${RESET}"
            echo "[${CYAN}${BOLD} INFO ${RESET}] ${BLUE}${BOLD}${GREEN}wlan0: ${RESET}IP         ${MAGENTA}$_IP_WLAN0${RESET}"
            echo "[${CYAN}${BOLD} INFO ${RESET}] ${BLUE}${BOLD}${GREEN}wlan0: ${RESET}SSID       ${YELLOW}$_SSID_WLAN0${RESET}"
            echo "[${CYAN}${BOLD} INFO ${RESET}] ${BLUE}${BOLD}${GREEN}wlan0: ${RESET}Frequency  ${YELLOW}$_FREQ_WLAN0 MHz${RESET}"
            echo "[${CYAN}${BOLD} INFO ${RESET}] ${BLUE}${BOLD}${GREEN}wlan0: ${RESET}Type       ${YELLOW}$_ENC_WLAN0${RESET}"
        fi
        exit 0
    fi
else
    exit 1
fi