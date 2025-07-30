#!/bin/bash

echo "Please enter the URL of the webpage you want to scrape (e.g., https://example.com):"
read URL

if [ -z "$URL" ]; then
    echo "Error: No URL provided. Exiting."
    exit 1
fi

echo "Please enter the output file where the page title will be saved (e.g., page_title.txt):"
read OUTPUT_FILE

if [ -z "$OUTPUT_FILE" ]; then
    echo "Error: No output file path provided. Exiting."
    exit 1
fi

echo "Fetching the webpage and extracting title from $URL..."
TITLE=$(curl -s "$URL" | grep -oP '(?<=<title>)(.*?)(?=</title>)')

LOG_FILE="/var/log/web_scraper.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "==================== Web Scraping Report ====================" >> $LOG_FILE
echo "Scraping started at: $DATE" >> $LOG_FILE

if [ -n "$TITLE" ]; then
    # Save title to output file
    echo "$TITLE" > "$OUTPUT_FILE"
    echo "Successfully scraped the following title:" >> $LOG_FILE
    echo "$TITLE" >> $LOG_FILE
else
    echo "Failed to scrape title or title tag not found." >> $LOG_FILE
fi

echo "==================== End of Report ====================" >> $LOG_FILE

cat $LOG_FILE
