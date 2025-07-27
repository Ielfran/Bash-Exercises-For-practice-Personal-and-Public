#!/bin/bash

server_name=${hostname}

function memory_check(){
    echo ""
    echo "Memory usage on ${server_name} is:" 
    free -h
    echo ""
}

function cpu_check(){
    echo ""
    echo "CPU load on ${server_name} is:"
    echo ""
    uptime
    echo ""
}

function tcp_check(){
    echo ""
    echo "TCP connection on ${server_name}:"
    echo ""
    cat /proc/net/tcp | wc -l
    echo ""
}

function kernel_check(){
    echo ""
    echo "Kernel version on ${server_name} is:"
    echo ""
    uname -r
    echo ""
}

function all_checks(){
    memory_check
    cpu_check
    tcp_check
    kernel_check
}

function help(){
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -m, --memory    Check memory usage"
    echo "  -c, --cpu       Check CPU load"
    echo "  -t, --tcp       Check number of TCP connections"
    echo "  -k, --kernel    Check kernel version"
    echo "  -a, --all       Perform all checks"
    echo "  -h, --help      Display this help message"
    echo ""
}


if [ $# -eq 0 ]; then
    help
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in 
        -m | --memory)
            memory_check
            ;;
        -c | --cpu)
            cpu_check
            ;;
        -t | --tcp)
            tcp_check
            ;;
        -k | --kernel)
            kernel_check
            ;;
        -a | --all)
            all_checks
            ;;
        -h | --help)
            help
            ;;
        *)
            echo "Invalid:"
            help 
            exit 1
            ;;
        esac
    shift 
done
