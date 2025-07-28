#!/bin/bash

if [ $# -ne 2 ]; then
    echo "Usage: $0 old_extension new_extension"
    exit 1
fi

for file in *.$1; do
    mv "$file" "${file%.$1}.$2"
done

