#!/bin/bash

usage() {
    echo "Usage: $0 [directory] [-s (sort by size)]"
    exit 1
}

DIR="."
SORT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--sort)
            SORT=true
            shift
            ;;
        -*)
            usage
            ;;
        *)
            DIR="$1"
            shift
            ;;
    esac
done

if [ ! -d "$DIR" ]; then
    echo "Error: '$DIR' is not a valid directory."
    exit 1
fi

echo "Disk usage in directory: $DIR"

if $SORT; then
    du -sh "$DIR"/* 2>/dev/null | sort -hr
else
    du -sh "$DIR"/* 2>/dev/null
fi
