#!/bin/bash

# Set colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo -e "Please run with:"
    echo -e "sudo $0"
    exit 1
fi

# Display title
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}          CasaOS Uninstaller             ${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Display warning message
echo -e "${YELLOW}Warning: This script will uninstall CasaOS${NC}"
echo -e "${YELLOW}Please select an option:${NC}"
echo -e "  1) Remove CasaOS core components only (keep installed apps)"
echo -e "  2) Complete uninstall (including all apps installed via CasaOS)"
echo -e "  3) Cancel"
echo
read -p "Choose [1-3] (default:1): " choice
echo

case $choice in
    1)
        echo -e "${GREEN}Selected: Remove CasaOS core components only${NC}"
        REMOVE_APPS=false
        ;;
    2)
        echo -e "${GREEN}Selected: Complete uninstall (including all apps)${NC}"
        REMOVE_APPS=true
        # Second confirmation
        echo -e "\n${RED}Warning: This will delete all apps installed via CasaOS and their data!${NC}"
        read -p "Are you sure you want to continue? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Operation cancelled${NC}"
            exit 0
        fi
        ;;
    *)
        echo -e "${YELLOW}Operation cancelled${NC}"
        exit 0
        ;;
esac

# Function: Execute command and check status
run_command() {
    echo -e "\n${GREEN}[Executing]${NC} $1"
    eval $1
    local status=$?
    if [ $status -ne 0 ]; then
        echo -e "${YELLOW}[Warning] Command may have failed: $1${NC}"
        # Continue execution even if command fails
    fi
    return $status
}

# Stop and disable CasaOS services
echo -e "\n${GREEN}>>> Stopping and disabling CasaOS services...${NC}"
services=(
    "casaos.service"
    "casaos-gateway.service"
    "casaos-message-bus.service"
    "casaos-user-service.service"
    "casaos-local-storage.service"
    "casaos-app-management.service"
    "devmon@devmon.service"
)

for service in "${services[@]}"; do
    run_command "systemctl stop $service 2>/dev/null"
    run_command "systemctl disable $service 2>/dev/null"
    run_command "systemctl reset-failed $service 2>/dev/null"
done

# Remove system service files
echo -e "\n${GREEN}>>> Removing system service files...${NC}"
run_command "rm -f /etc/systemd/system/casaos*.service"
run_command "rm -f /etc/systemd/system/devmon@.service"

# Remove program files
echo -e "\n${GREEN}>>> Removing program files...${NC}"
run_command "rm -f /usr/bin/casaos*"
run_command "rm -f /usr/local/bin/casaos*"

# Remove configuration and data files
echo -e "\n${GREEN}>>> Removing configuration and data files...${NC}"
run_command "rm -rf /etc/casaos"
run_command "rm -rf /var/lib/casaos"
run_command "rm -rf /var/log/casaos"
run_command "rm -rf /usr/share/casaos"
run_command "rm -rf /var/cache/casaos"

# If user chose complete uninstall, remove all apps
if [ "$REMOVE_APPS" = true ]; then
    echo -e "\n${GREEN}>>> Removing all applications installed via CasaOS...${NC}"

    # 1. Stop and remove all containers managed by CasaOS
    echo -e "\n${YELLOW}Finding and stopping all containers managed by CasaOS...${NC}"
    casaos_containers=$(docker ps -a --format "{{.ID}} {{.Names}}" | grep -E 'casaos|app-|casaos_' | cut -d' ' -f1)

    if [ -n "$casaos_containers" ]; then
        echo "Found the following CasaOS containers:"
        docker ps -a --format "{{.ID}}  {{.Names}}  {{.Image}}" | grep -E 'casaos|app-|casaos_'
        
        # Stop and remove containers
        echo -e "\n${YELLOW}Stopping and removing these containers...${NC}"
        for container in $casaos_containers; do
            run_command "docker stop $container 2>/dev/null"
            run_command "docker rm -f $container 2>/dev/null"
        done
    else
        echo "No CasaOS containers found"
    fi

    # 2. Find and remove all CasaOS-related images
    echo -e "\n${YELLOW}Finding and removing CasaOS-related images...${NC}"
    casaos_images=$(docker images --format "{{.ID}} {{.Repository}}" | grep -E 'casaos|icewhale|linuxserver' | cut -d' ' -f1 | sort -u)

    if [ -n "$casaos_images" ]; then
        echo "Found the following CasaOS-related images:"
        docker images --format "{{.Repository}}:{{.Tag}}" | grep -E 'casaos|icewhale|linuxserver'
        
        echo -e "\n${YELLOW}Removing these images...${NC}"
        for image in $casaos_images; do
            run_command "docker rmi -f $image 2>/dev/null"
        done
    else
        echo "No CasaOS-related images found"
    fi

    # 3. Find and remove all CasaOS-related volumes
    echo -e "\n${YELLOW}Finding and removing CasaOS-related volumes...${NC}"
    casaos_volumes=$(docker volume ls --format "{{.Name}}" | grep -E 'casaos|app-')

    if [ -n "$casaos_volumes" ]; then
        echo "Found the following CasaOS volumes:"
        echo "$casaos_volumes"
        
        echo -e "\n${YELLOW}Removing these volumes...${NC}"
        for volume in $casaos_volumes; do
            run_command "docker volume rm $volume 2>/dev/null"
        done
    else
        echo "No CasaOS volumes found"
    fi

    # 4. Clean up networks
    echo -e "\n${YELLOW}Cleaning up networks created by CasaOS...${NC}"
    casaos_networks=$(docker network ls --format "{{.Name}}" | grep -E 'casaos|app-')

    if [ -n "$casaos_networks" ]; then
        echo "Found the following networks created by CasaOS:"
        echo "$casaos_networks"
        
        echo -e "\n${YELLOW}Removing these networks...${NC}"
        for network in $casaos_networks; do
            run_command "docker network rm $network 2>/dev/null"
        done
    else
        echo "No networks created by CasaOS found"
    fi
fi

# Remove CasaOS user and group
echo -e "\n${GREEN}>>> Removing CasaOS user and group...${NC}"
run_command "userdel -r casaos 2>/dev/null"
run_command "groupdel casaos 2>/dev/null"

# Clean up temporary files
echo -e "\n${GREEN}>>> Cleaning up temporary files...${NC}"
run_command "rm -rf /tmp/casaos-*"

# Reload systemd
echo -e "\n${GREEN}>>> Reloading systemd configuration...${NC}"
run_command "systemctl daemon-reload"
run_command "systemctl reset-failed"

# Completion message
echo -e "\n${GREEN}>>> CasaOS has been successfully uninstalled!${NC}"
if [ "$REMOVE_APPS" = true ]; then
    echo -e "${GREEN}>>> All apps installed via CasaOS and their data have been removed.${NC}"
else
    echo -e "${GREEN}>>> Note: Apps installed via CasaOS have been preserved.${NC}"
fi

# Docker removal notice
echo -e "\n${YELLOW}========== IMPORTANT NOTICE ==========${NC}"
echo -e "${YELLOW}This script does NOT remove Docker itself.${NC}"
echo -e "${YELLOW}If you want to remove Docker, you can use the following commands:${NC}"
echo -e "\n${BLUE}For Ubuntu/Debian:${NC}"
echo -e "sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin"
echo -e "sudo apt-get autoremove -y"
echo -e "sudo rm -rf /var/lib/docker"
echo -e "sudo rm -rf /var/lib/containerd"
echo -e "\n${BLUE}For CentOS/RHEL:${NC}"
echo -e "sudo yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin"
echo -e "sudo rm -rf /var/lib/docker"
echo -e "sudo rm -rf /var/lib/containerd"
echo -e "\n${YELLOW}=====================================${NC}"

# Ask for reboot
read -p "Do you want to reboot the system now? (y/N): " reboot_now
if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
    echo -e "\n${GREEN}System will reboot in 5 seconds...${NC}"
    echo -e "Press Ctrl+C to cancel"
    sleep 5
    reboot
else
    echo -e "\n${GREEN}Please reboot the system to complete the uninstallation.${NC}"
fi

exit 0