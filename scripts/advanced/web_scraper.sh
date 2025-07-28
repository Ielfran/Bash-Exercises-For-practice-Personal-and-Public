#!/bin/bash

echo "Please enter the URL of the webpage you want to scrape (e.g., https://example.com/blog):"
read URL

if [ -z "$URL" ]; then
    echo "Error: No URL provided. Exiting."
    exit 1
fi

echo "Please enter the output file where the titles will be saved (e.g., scraped_titles.txt):"
read OUTPUT_FILE

if [ -z "$OUTPUT_FILE" ]; then
    echo "Error: No output file path provided. Exiting."
    exit 1
fi

echo "Fetching the webpage and extracting titles from $URL..."
curl -s $URL | grep -oP '(?<=<h2>).*(?=</h2>)' > $OUTPUT_FILE

LOG_FILE="/var/log/web_scraper.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "==================== Web Scraping Report ====================" >> $LOG_FILE
echo "Scraping started at: $DATE" >> $LOG_FILE

if [ -s $OUTPUT_FILE ]; then
    echo "Successfully scraped the following titles:" >> $LOG_FILE
    cat $OUTPUT_FILE >> $LOG_FILE
else
    echo "No titles found or scraping failed." >> $LOG_FILE
fi

echo "==================== End of Report ====================" >> $LOG_FILE

cat $LOG_FILE
