#!/bin/bash

echo "Enter the directory path:"
read dir

if [ -d "$dir" ]; then
    echo "Files in $dir:"
    ls "$dir"
else
    echo "$dir is not a valid directory."
fi
