#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 filename"
    exit 1
fi

if [ -f "$1" ]; then
    wc -l < "$1"
else
    echo "File not found!"
fi
