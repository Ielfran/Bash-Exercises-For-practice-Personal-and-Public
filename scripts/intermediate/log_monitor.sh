#!/bin/bash

usage() {
    echo "Usage: $0 log_file [--filter keyword]"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

FILE="$1"
FILTER=""
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --filter)
            FILTER="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

if [ ! -f "$FILE" ]; then
    echo "Error: File '$FILE' does not exist."
    exit 1
fi

echo "Monitoring '$FILE'..."

if [ -n "$FILTER" ]; then
    echo "Filtering lines with keyword: $FILTER"
    tail -Fn0 "$FILE" | grep --color=always --line-buffered "$FILTER"
else
    tail -Fn0 "$FILE"
fi
