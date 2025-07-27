#!/bin/bash
# This script checks if a file exists.

echo "Enter the filename to check:"
read filename

if [ -e "$filename" ]; then
    echo "File exists."
else
    echo "File does not exist."
fi
