#!/bin/bash

BACKENDS=("http://localhost:8081" "http://localhost:8082" "http://localhost:8083")

LB_PORT=8080

STRATEGY="round-robin"

HEALTH_CHECK_TIMEOUT=2

CURRENT=0

check_backend() {
    local backend_host=$(echo $1 | cut -d'/' -f3)
    local host=$(echo $backend_host | cut -d':' -f1)
    local port=$(echo $backend_host | cut -d':' -f2)
    (</dev/tcp/$host/$port) &>/dev/null
    return $?
}

next_backend() {
    local max_retries=${#BACKENDS[@]}
    for ((i=0; i<max_retries; i++)); do
        if [ "$STRATEGY" == "random" ]; then
            CURRENT=$(( RANDOM % ${#BACKENDS[@]} ))
        else # round-robin
            CURRENT=$(( (CURRENT + 1) % ${#BACKENDS[@]} ))
        fi

        local backend=${BACKENDS[$CURRENT]}
        if check_backend $backend; then
            echo "$backend"
            return
        else
            echo "[$(date +'%T')] WARNING: Backend $backend is down." >&2
        fi
    done
    echo ""
}

handle_request() {
    read -r request_line

    local backend=$(next_backend)

    if [ -z "$backend" ]; then
        echo -ne "HTTP/1.1 503 Service Unavailable\r\n"
        echo -ne "Content-Type: text/plain\r\n\r\n"
        echo -ne "No backend servers available.\r\n"
        return
    fi

    echo "[$(date +'%T')] Forwarding request to: $backend"

    {
        echo -e "$request_line\r"
        while read -r header && [ -n "$header" ] && [[ "$header" != $'\r' ]]; do
            echo -e "$header\r"
        done
        echo -e "\r"
    } | nc $(echo $backend | cut -d'/' -f3 | tr ':' ' ') | {
        while IFS= read -r line; do
            echo -ne "$line\r\n"
        done
    }
}

trap "echo -e '\nShutting down load balancer...'; kill 0; exit 0" SIGINT

echo "Starting load balancer on port $LB_PORT..."
echo "Backends: ${BACKENDS[*]}"
echo "Strategy: $STRATEGY"
echo "Press Ctrl+C to stop."

FIFO=/tmp/lb_fifo
[[ -p $FIFO ]] && rm $FIFO
mkfifo $FIFO

while true; do
    nc -l -p "$LB_PORT" < $FIFO | handle_request > $FIFO
done