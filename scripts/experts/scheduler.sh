#!/bin/bash

LOG_DIR="$HOME/.process_scheduler/logs"
TASK_FILE="$HOME/.process_scheduler/scheduled_tasks.txt"
mkdir -p "$LOG_DIR"
mkdir -p "$(dirname "$TASK_FILE")"

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

trap "echo -e '\n${RED}Exiting...${RESET}'; exit 0" SIGINT

print_menu() {
    clear
    echo -e "${CYAN}====================================${RESET}"
    echo -e "         🕒 ${GREEN}Process Scheduler${RESET}         "
    echo -e "${CYAN}====================================${RESET}"
    echo "1. Schedule a task (run now)"
    echo "2. Schedule a task (run later)"
    echo "3. View scheduled tasks"
    echo "4. Cancel a scheduled task"
    echo "5. Exit"
    echo -e "${CYAN}====================================${RESET}"
}

run_now() {
    read -rp "Enter the command to run: " cmd
    [[ -z "$cmd" ]] && echo -e "${RED}Command cannot be empty.${RESET}" && return

    log_file="$LOG_DIR/task_$(date +%Y%m%d_%H%M%S).log"
    echo -e "${YELLOW}Running in background... Logs: $log_file${RESET}"
    nohup bash -c "$cmd" >> "$log_file" 2>&1 &
    echo -e "${GREEN}Task started with PID: $!${RESET}"
}
run_later() {
    read -rp "Enter the command to run: " cmd
    [[ -z "$cmd" ]] && echo -e "${RED}Command cannot be empty.${RESET}" && return

    echo -e "Choose scheduling method:"
    echo -e "  1. In X seconds/minutes"
    echo -e "  2. At a specific time (requires 'at' command)"
    read -rp "Option [1-2]: " sched_type

    log_file="$LOG_DIR/task_$(date +%Y%m%d_%H%M%S).log"

    if [[ "$sched_type" == "1" ]]; then
        read -rp "Run after how many seconds? " delay
        [[ ! "$delay" =~ ^[0-9]+$ ]] && echo -e "${RED}Delay must be a number.${RESET}" && return
        nohup bash -c "sleep $delay && $cmd >> \"$log_file\" 2>&1" &
        echo "$! | +${delay}s | $cmd | $log_file" >> "$TASK_FILE"
        echo -e "${GREEN}Task scheduled in $delay seconds. Logs: $log_file${RESET}"
    elif [[ "$sched_type" == "2" ]]; then
        if ! command -v at &>/dev/null; then
            echo -e "${RED}The 'at' command is not available on this system.${RESET}"
            return
        fi
        read -rp "When to run it (e.g., 'now + 1 minute', 'tomorrow 5pm'): " time
        job_id=$(echo "$cmd >> \"$log_file\" 2>&1" | at "$time" 2>/dev/null | awk '{print $2}')
        if [[ $? -eq 0 && -n "$job_id" ]]; then
            echo "$job_id | $time | $cmd | $log_file" >> "$TASK_FILE"
            echo -e "${GREEN}Task scheduled (Job ID: $job_id). Logs: $log_file${RESET}"
        else
            echo -e "${RED}Failed to schedule task. Check your time format or 'atd' service.${RESET}"
        fi
    else
        echo -e "${RED}Invalid scheduling option.${RESET}"
    fi
}

view_tasks() {
    echo -e "${CYAN}======= Scheduled Tasks =======${RESET}"
    if [[ -f "$TASK_FILE" && -s "$TASK_FILE" ]]; then
        nl -w2 -s". " "$TASK_FILE"
    else
        echo -e "${YELLOW}No tasks scheduled.${RESET}"
    fi
    echo -e "${CYAN}===============================${RESET}"
}

cancel_task() {
    view_tasks
    [[ ! -s "$TASK_FILE" ]] && return

    read -rp "Enter the line number of the task to cancel: " num
    [[ ! "$num" =~ ^[0-9]+$ ]] && echo -e "${RED}Invalid selection.${RESET}" && return

    task_line=$(sed -n "${num}p" "$TASK_FILE")
    [[ -z "$task_line" ]] && echo -e "${RED}Invalid selection.${RESET}" && return

    job_id=$(echo "$task_line" | cut -d '|' -f1 | tr -d ' ')
    atrm "$job_id" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        sed -i "${num}d" "$TASK_FILE"
        echo -e "${GREEN}Cancelled Job ID $job_id.${RESET}"
    else
        echo -e "${RED}Failed to cancel Job ID $job_id. It may have already run.${RESET}"
    fi
}

main() {
    while true; do
        print_menu
        read -rp "Choose an option [1-5]: " choice
        case $choice in
            1) run_now ;;
            2) run_later ;;
            3) view_tasks ;;
            4) cancel_task ;;
            5) echo -e "${GREEN}Goodbye!${RESET}"; exit 0 ;;
            *) echo -e "${RED}Invalid choice. Try again.${RESET}" ;;
        esac
        read -rp "Press enter to continue..."
    done
}

main