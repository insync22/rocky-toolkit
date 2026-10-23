#!/bin/bash
# backup.sh - archives a folder into ~/backups with a date in the name
# Usage: ./backup.sh /path/to/folder

SOURCE="$1"
DEST="$HOME/backups"

# Check that the user gave us a folder
if [ -z "$SOURCE" ]; then
    echo "Usage: $0 /path/to/folder"
    exit 1
fi

# Check that the folder actually exists
if [ ! -d "$SOURCE" ]; then
    echo "Error: '$SOURCE' is not a folder or does not exist."
    exit 1
fi

# Make the backup folder if it is missing
mkdir -p "$DEST"

# Build the file name: foldername_date-time.tar.gz
NAME=$(basename "$SOURCE")
STAMP=$(date +%Y-%m-%d_%H-%M)
FILE="$DEST/${NAME}_${STAMP}.tar.gz"

# Create the archive
tar -czf "$FILE" -C "$(dirname "$SOURCE")" "$NAME"

# Report the result
if [ $? -eq 0 ]; then
    echo "Backup created: $FILE"
    echo "Size: $(du -h "$FILE" | cut -f1)"
else
    echo "Backup failed."
    exit 1
fi
