#!/bin/bash

LOG_FILE="/var/log/sys_monitor.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "==================== System Monitoring Report ====================" >> $LOG_FILE
echo "Report generated on: $DATE" >> $LOG_FILE

echo -e "\nCPU Usage:" >> $LOG_FILE
top -bn1 | grep "Cpu(s)" >> $LOG_FILE

echo -e "\nMemory Usage:" >> $LOG_FILE
free -h >> $LOG_FILE

echo -e "\nDisk Usage:" >> $LOG_FILE
df -h >> $LOG_FILE

echo -e "\nRunning Processes:" >> $LOG_FILE
ps aux --sort=-%mem | head -n 10 >> $LOG_FILE

echo -e "\nNetwork Usage:" >> $LOG_FILE
netstat -tulnp >> $LOG_FILE

echo "==================== End of Report ====================" >> $LOG_FILE

cat $LOG_FILE
