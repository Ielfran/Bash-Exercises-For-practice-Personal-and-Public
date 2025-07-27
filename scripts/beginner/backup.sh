#!/bin/bash

echo "Enter the directory to backup:"
read source_dir
echo "Enter the destination directory:"
read dest_dir

if [ -d "$source_dir" ]; then
    timestamp=$(date +"%Y%m%d_%H%M%S")
    backup_dir="$dest_dir/backup_$timestamp"
    mkdir -p "$backup_dir"
    cp -r "$source_dir"/* "$backup_dir"
    echo "Backup of $source_dir completed to $backup_dir."
else
    echo "The source directory does not exist."
fi

