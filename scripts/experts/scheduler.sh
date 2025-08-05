#!/bin/bash

LOG_DIR="$HOME/.process_scheduler/logs"
TASK_FILE="$HOME/.process_scheduler/scheduled_tasks.txt"
mkdir -p "$LOG_DIR"
mkdir -p "$(dirname "$TASK_FILE")"

print_menu() {
    clear
    echo "===================================="
    echo "         🕒 Process Scheduler        "
    echo "===================================="
    echo "1. Schedule a task (run now)"
    echo "2. Schedule a task (run later)"
    echo "3. View scheduled tasks"
    echo "4. Cancel a scheduled task"
    echo "5. Exit"
    echo "===================================="
}

run_now() {
    read -rp "Enter the command to run: " cmd
    log_file="$LOG_DIR/task_$(date +%s).log"
    echo "Running in background... Logs: $log_file"
    bash -c "$cmd" >> "$log_file" 2>&1 &
    echo "Task [$!] started with PID: $!"
}

run_later() {
    if ! command -v at &>/dev/null; then
        echo "The 'at' command is not available on this system."
        return
    fi
    read -rp "Enter the command to run: " cmd
    read -rp "When to run it (e.g., 'now + 1 minute', 'tomorrow 5pm'): " time
    log_file="$LOG_DIR/task_$(date +%s).log"
    
    echo "$cmd >> \"$log_file\" 2>&1" | at "$time" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo "$time | $cmd | $log_file" >> "$TASK_FILE"
        echo "Task scheduled. Output will be in: $log_file"
    else
        echo "Failed to schedule task. Please check your time format or 'atd' service."
    fi
}

view_tasks() {
    echo "======= Scheduled Tasks ======="
    if [[ -f "$TASK_FILE" && -s "$TASK_FILE" ]]; then
        nl "$TASK_FILE"
    else
        echo "No tasks scheduled."
    fi
    echo "==============================="
}

cancel_task() {
    view_tasks
    read -rp "Enter the line number of the task to cancel: " num
    task_line=$(sed -n "${num}p" "$TASK_FILE")
    [[ -z "$task_line" ]] && echo "Invalid selection." && return

    # Get the 'at' job ID
    job_list=$(atq)
    while IFS= read -r line; do
        job_id=$(echo "$line" | awk '{print $1}')
        at_time=$(at -c "$job_id" | tail -n +2)
        if [[ "$at_time" == *"${task_line#*| }"* ]]; then
            atrm "$job_id"
            sed -i "${num}d" "$TASK_FILE"
            echo "Cancelled job ID $job_id"
            return
        fi
    done <<< "$job_list"

    echo "Unable to match or cancel the task."
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
            5) echo "Goodbye!"; exit 0 ;;
            *) echo "Invalid choice. Try again." ;;
        esac
        read -rp "Press enter to continue..."
    done
}

main
