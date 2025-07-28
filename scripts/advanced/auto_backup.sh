#!/bin/bash

echo "Please enter the source directory you want to back up (e.g., /home/ielfran/Downloads):"
read SOURCE_DIR

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist. Exiting."
    exit 1
fi

echo "Please enter the destination directory where the backup will be stored (e.g., /mnt/backups):"
read BACKUP_DIR

if [ ! -d "$BACKUP_DIR" ]; then
    echo "Error: Destination directory '$BACKUP_DIR' does not exist. Exiting."
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"

LOG_FILE="/var/log/auto_backup.log"

echo "==================== Backup Report ====================" >> $LOG_FILE
echo "Backup started at: $(date)" >> $LOG_FILE

echo "Creating backup: $BACKUP_FILE" >> $LOG_FILE
tar -czf $BACKUP_FILE $SOURCE_DIR

if [ $? -eq 0 ]; then
    echo "Backup successfully created: $BACKUP_FILE" >> $LOG_FILE
else
    echo "Backup failed!" >> $LOG_FILE
fi

echo "==================== End of Report ====================" >> $LOG_FILE

cat $LOG_FILE
