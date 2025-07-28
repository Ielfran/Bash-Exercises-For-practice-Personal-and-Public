#!/bin/bash

if [ $# -eq 0 ]; then
    echo "Usage: $0 number1 number2 ..."
    exit 1
fi

largest=$1

for num in "$@"; do
    if (( num > largest )); then
        largest=$num
    fi
done

echo "Largest number: $largest"

