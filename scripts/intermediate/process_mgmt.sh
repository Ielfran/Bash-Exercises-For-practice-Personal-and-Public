#!/bin/bash

usage() {
    echo "Usage: $0 process_name"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

PROCESS_NAME="$1"

echo "Searching for processes matching '$PROCESS_NAME'..."
MATCHES=$(ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu | grep -i "$PROCESS_NAME" | grep -v grep)

if [ -z "$MATCHES" ]; then
    echo "No process found matching '$PROCESS_NAME'"
    exit 0
fi

echo "PID     USER     COMMAND         %CPU  %MEM"
echo "$MATCHES"

read -p "Would you like to kill any of these processes? (y/n): " CONFIRM
if [[ $CONFIRM == [Yy]* ]]; then
    read -p "Enter PID to kill: " PID
    if kill -9 "$PID" 2>/dev/null; then
        echo "Process $PID terminated."
    else
        echo "Failed to terminate process $PID (may require sudo)."
    fi
fi

