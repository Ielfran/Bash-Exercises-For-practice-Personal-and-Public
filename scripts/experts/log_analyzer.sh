#!/bin/bash

LOG_FILE=${1:-/var/log/nginx/access.log}

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

if [[ ! -f "$LOG_FILE" ]]; then
    echo -e "${RED}Log file not found: $LOG_FILE${RESET}"
    exit 1
fi

menu() {
    clear
    echo -e "${CYAN}==============================${RESET}"
    echo -e "      ${GREEN}Log Analyzer Tool${RESET}"
    echo -e "${CYAN}==============================${RESET}"
    echo "1. Show top IP addresses"
    echo "2. Show most requested URLs"
    echo "3. Show top user agents"
    echo "4. Show HTTP status code counts"
    echo "5. Filter logs by date"
    echo "6. Show error (4xx, 5xx) requests"
    echo "7. Summary report"
    echo "8. Exit"
    echo -e "${CYAN}==============================${RESET}"
}

top_ips() {
    echo -e "${YELLOW}Top IP addresses:${RESET}"
    awk '{print $1}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -20
}

top_urls() {
    echo -e "${YELLOW}Most requested URLs:${RESET}"
    awk '{print $7}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -20
}

top_agents() {
    echo -e "${YELLOW}Top User Agents:${RESET}"
    awk -F\" '{print $6}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -20
}

status_codes() {
    echo -e "${YELLOW}HTTP Status Codes:${RESET}"
    awk '{print $9}' "$LOG_FILE" | sort | uniq -c | sort -nr
}

filter_by_date() {
    read -rp "Enter date (e.g., 10/Feb/2025): " date
    echo -e "${YELLOW}Logs for $date:${RESET}"
    grep "$date" "$LOG_FILE"
}

error_requests() {
    echo -e "${YELLOW}Error Requests (4xx, 5xx):${RESET}"
    awk '$9 ~ /^[45]/ {print $0}' "$LOG_FILE"
}

summary_report() {
    echo -e "${CYAN}====== SUMMARY REPORT ======${RESET}"
    echo -e "${GREEN}Total requests:${RESET} $(wc -l < "$LOG_FILE")"
    echo -e "${GREEN}Unique IPs:${RESET} $(awk '{print $1}' "$LOG_FILE" | sort -u | wc -l)"
    echo -e "${GREEN}Top IP:${RESET} $(awk '{print $1}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -1)"
    echo -e "${GREEN}Top URL:${RESET} $(awk '{print $7}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -1)"
    echo -e "${GREEN}Most common status:${RESET} $(awk '{print $9}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -1)"
    echo -e "${CYAN}===========================${RESET}"
}

while true; do
    menu
    read -rp "Choose an option [1-8]: " choice
    case $choice in
        1) top_ips ;;
        2) top_urls ;;
        3) top_agents ;;
        4) status_codes ;;
        5) filter_by_date ;;
        6) error_requests ;;
        7) summary_report ;;
        8) echo -e "${GREEN}Goodbye!${RESET}"; exit 0 ;;
        *) echo -e "${RED}Invalid choice.${RESET}" ;;
    esac
    read -rp "Press enter to continue..."
done