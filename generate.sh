#!/bin/bash

# Script to generate a directory listing (excluding .gd.uid, .tmp, and .import files)
# and concatenate relevant Godot project files.
# This script relies on 'git' being installed and your project being a Git repository.

# --- Configuration ---
# Output file for the directory listing
DIR_LISTING_FILE="directory_listing.txt"

# Output file for the concatenated code and scene files
CONCATENATED_CODE_FILE="project_code_and_scenes.txt"

# File extensions and specific filenames to include in the concatenated file.
# .gd.uid, .tmp, and .import files are intentionally excluded from concatenation
# as they are not typically part of the source code you'd want to combine.
INCLUDE_PATTERNS=(".gd" ".gdshader" ".tscn" ".scn" ".tres" "project.godot")

# --- Script Logic ---

echo "Starting Godot project export script..."

# 1. Generate directory listing (respecting .gitignore AND excluding specified patterns)
echo "Generating directory listing (excluding .gd.uid, .tmp, .import files): $DIR_LISTING_FILE"
# We pipe git ls-files through grep -v with an extended regex
# to exclude lines ending with .gd.uid, .tmp, or .import
if git ls-files | grep -v -E '\.gd\.uid$|\.tmp$|\.import$' > "$DIR_LISTING_FILE"; then
  echo "Successfully created $DIR_LISTING_FILE"
else
  # This error might occur if git ls-files fails or if grep fails
  echo "Error: Failed to generate directory listing. Is this a git repository? Or an issue with grep?"
  exit 1
fi

echo "" # Newline for better readability

# 2. Concatenate specified project files
echo "Concatenating project files into: $CONCATENATED_CODE_FILE"

# Clear the output file if it already exists
> "$CONCATENATED_CODE_FILE" # This creates an empty file or truncates an existing one

# Build the grep pattern dynamically from INCLUDE_PATTERNS
# This pattern will be used to filter files from 'git ls-files' for concatenation.
# Example target pattern: '\.gd$|\.gdshader$|\.tscn$|\.scn$|\.tres$|project\.godot$'
CONCAT_PATTERN=""
for item in "${INCLUDE_PATTERNS[@]}"; do
  # Escape dots for literal matching in regex and anchor to the end of the filename.
  # For extensions like ".gd", it becomes "\.gd$".
  # For full filenames like "project.godot", it becomes "project\.godot$".
  escaped_item=$(echo "$item" | sed 's/\./\\./g') # Escape all dots
  current_regex_part="${escaped_item}$"

  if [ -z "$CONCAT_PATTERN" ]; then
    CONCAT_PATTERN="$current_regex_part"
  else
    CONCAT_PATTERN="$CONCAT_PATTERN|$current_regex_part"
  fi
done

echo "Using pattern for file types to concatenate: $CONCAT_PATTERN"

# Find files matching the patterns and concatenate them.
# 'git ls-files' lists all tracked files.
# 'grep -E "$CONCAT_PATTERN"' filters this list to include only desired files.
git ls-files | grep -E "$CONCAT_PATTERN" | while IFS= read -r file; do
  if [ -f "$file" ]; then # Check if it's a regular file
    echo "--- START OF FILE: $file ---" >> "$CONCATENATED_CODE_FILE"
    cat "$file" >> "$CONCATENATED_CODE_FILE"
    echo "" >> "$CONCATENATED_CODE_FILE" # Add a newline after the file content for readability
    echo "--- END OF FILE: $file ---" >> "$CONCATENATED_CODE_FILE"
    echo "" >> "$CONCATENATED_CODE_FILE" # Add an extra newline for spacing between files
    echo "Appended: $file"
  else
    echo "Warning: '$file' listed by git ls-files and matched by pattern, but not found or not a regular file. Skipping."
  fi
done

# Check status of concatenation
if [ -f "$CONCATENATED_CODE_FILE" ]; then
    if [ -s "$CONCATENATED_CODE_FILE" ]; then # Check if file has size > 0
        echo "Successfully concatenated files into $CONCATENATED_CODE_FILE"
    else
        # This can happen if no files match the INCLUDE_PATTERNS
        echo "No files found matching the specified patterns for concatenation. $CONCATENATED_CODE_FILE is empty."
    fi
else
  echo "Error: $CONCATENATED_CODE_FILE was not created. Something went wrong during file concatenation."
  # exit 1 # Optionally exit on error here
fi

echo ""
echo "Script finished."
echo "Please find your files:"
echo "1. Directory Listing (without .gd.uid, .tmp, .import): $DIR_LISTING_FILE"
echo "2. Concatenated Code & Scenes: $CONCATENATED_CODE_FILE"

