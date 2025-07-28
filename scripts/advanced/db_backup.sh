#!/bin/bash

echo "Please enter the MySQL database username (e.g., your_username):"
read DB_USER

echo "Please enter the MySQL database password:"
read -s DB_PASS

echo "Please enter the MySQL database name (e.g., your_database):"
read DB_NAME

if [ -z "$DB_USER" ] || [ -z "$DB_PASS" ] || [ -z "$DB_NAME" ]; then
    echo "Error: Missing database credentials. Exiting."
    exit 1
fi

echo "Please enter the directory where backups will be stored (e.g., /mnt/db_backups):"
read BACKUP_DIR
if [ ! -d "$BACKUP_DIR" ]; then
    echo "Error: Destination directory '$BACKUP_DIR' does not exist. Exiting."
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/db_backup_$DB_NAME_$TIMESTAMP.sql.gz"

LOG_FILE="/var/log/db_backup.log"

echo "==================== Database Backup Report ====================" >> $LOG_FILE
echo "Backup started at: $(date)" >> $LOG_FILE

echo "Backing up database $DB_NAME to $BACKUP_FILE" >> $LOG_FILE
mysqldump -u $DB_USER -p$DB_PASS $DB_NAME | gzip > $BACKUP_FILE

if [ $? -eq 0 ]; then
    echo "Database backup successfully created: $BACKUP_FILE" >> $LOG_FILE
else
    echo "Database backup failed!" >> $LOG_FILE
fi

echo "==================== End of Report ====================" >> $LOG_FILE

cat $LOG_FILE
