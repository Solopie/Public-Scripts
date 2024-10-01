#!/bin/bash

# Redacted variables that are expected to be in environment:
# LOCAL_USERNAME=<REDACTED>
# VULTR_API_KEY=<REDACTED>

# Define the time file and the allowed time difference (30 minutes in seconds)
TIME_FILE="/home/$LOCAL_USERNAME/time"
TIME_LIMIT=$((30 * 60)) # 30 minutes in seconds

# Check if the time file exists
if [[ ! -f "$TIME_FILE" ]]; then
    echo $(date +%s) > $TIME_FILE
    exit 0
fi

# Read the timestamp from the file
FILE_TIMESTAMP=$(cat "$TIME_FILE")

# Get the current timestamp
CURRENT_TIMESTAMP=$(date +%s)

# Calculate the time difference
TIME_DIFF=$((CURRENT_TIMESTAMP - FILE_TIMESTAMP))

# If the time difference is greater than the limit, destroy the Vultr instance
if [[ "$TIME_DIFF" -gt "$TIME_LIMIT" ]]; then
    # Run the curl command to destroy the Vultr instance
    curl "https://api.vultr.com/v2/instances/$(curl http://169.254.169.254/v1/instance-v2-id)" \
         -X DELETE \
         -H "Authorization: Bearer ${VULTR_API_KEY}"
fi
