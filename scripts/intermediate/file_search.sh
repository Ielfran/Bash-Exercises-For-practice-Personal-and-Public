#!/bin/bash

if [ $# -ne 2 ]; then
    echo "Usage: $0 filename directory"
    exit 1
fi

find "$2" -type f -name "$1"
