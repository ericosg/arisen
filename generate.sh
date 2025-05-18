#!/bin/bash

# Script to generate a directory listing (excluding .gd.uid, .tmp, and .import files)
# and concatenate relevant Godot project files.
# This script relies on 'git' being installed and your project being a Git repository.

# --- Configuration ---
# Output file for the directory listing
DIR_LISTING_FILE="directory_listing.txt"

# Output file for the concatenated code and scene files
CONCATENATED_CODE_FILE="project_code_and_scenes.txt"

# File extensions to include in the concatenated file (add or remove as needed)
# Example: ".gd .gdshader .tscn .tres .project"
# For this script, we'll focus on common text-based Godot files.
# .gd.uid, .tmp, and .import files are intentionally excluded here.
INCLUDE_EXTENSIONS=(".gd" ".gdshader" ".tscn" ".scn" ".tres" "project.godot") # Added .tres and project.godot

# --- Script Logic ---

echo "Starting Godot project export script..."

# 1. Generate directory listing (respecting .gitignore AND excluding specified patterns)
echo "Generating directory listing (excluding .gd.uid, .tmp, .import files): $DIR_LISTING_FILE"
# We pipe git ls-files through grep -v multiple times or use a single extended regex
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

# Build the grep pattern dynamically from INCLUDE_EXTENSIONS
# e.g., '\.gd$|\.gdshader$|\.tscn$|\.scn$|\.tres$|project\.godot$'
PATTERN=""
for ext_or_filename in "${INCLUDE_EXTENSIONS[@]}"; do
  # Check if it's a full filename (like project.godot) or just an extension
  if [[ "$ext_or_filename" == *"."* && ! "$ext_or_filename" == .* ]]; then # Likely a full filename
    # Escape dots in filenames for literal matching
    escaped_item=$(echo "$ext_or_filename" | sed 's/\./\\./g')
    current_pattern="$escaped_item$"
  else # Likely an extension
    # Escape dots in extensions
    escaped_item=$(echo "$ext_or_filename" | sed 's/\./\\./g')
    current_pattern="\\$escaped_item$"
  fi

  if [ -z "$PATTERN" ]; then
    PATTERN="$current_pattern"
  else
    PATTERN="$PATTERN|$current_pattern"
  fi
done

echo "Using pattern for file types to concatenate: $PATTERN"

# Find files matching the extensions/filenames and concatenate them
# Note: This part still uses git ls-files directly, but grep filters for INCLUDE_EXTENSIONS,
# so excluded files won't be concatenated as long as their extensions/names are not in INCLUDE_EXTENSIONS.
git ls-files | grep -E "$PATTERN" | while IFS= read -r file; do
  if [ -f "$file" ]; then # Check if it's a file
    echo "--- START OF FILE: $file ---" >> "$CONCATENATED_CODE_FILE"
    cat "$file" >> "$CONCATENATED_CODE_FILE"
    echo "" >> "$CONCATENATED_CODE_FILE" # Add a newline after the file content
    echo "--- END OF FILE: $file ---" >> "$CONCATENATED_CODE_FILE"
    echo "" >> "$CONCATENATED_CODE_FILE" # Add an extra newline for spacing between files
    echo "Appended: $file"
  else
    echo "Warning: '$file' listed by git ls-files but not found or not a regular file. Skipping."
  fi
done

# Check status of concatenation
if [ -f "$CONCATENATED_CODE_FILE" ]; then
    if [ -s "$CONCATENATED_CODE_FILE" ]; then
        echo "Successfully concatenated files into $CONCATENATED_CODE_FILE"
    else
        echo "No files found matching the specified extensions/filenames for concatenation. $CONCATENATED_CODE_FILE is empty."
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

