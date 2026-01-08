#!/bin/bash

################################################################################
# Google Photos to Proton Drive Photos Migration Script for macOS
# 
# Purpose: Transform Google Photos Takeout exports into a clean, de-duplicated,
#          album-structured photo library with fixed EXIF/timestamps, suitable
#          for manual upload to Proton Drive's Photos section.
#
# What this script does:
#   1. Installs google-photos-takeout-helper to merge JSON metadata into files
#   2. Fixes creation dates and EXIF so files reflect correct time taken
#   3. De-duplicates photos across multiple Takeout archives
#   4. Organizes output into ALL_PHOTOS (by year) + per-album folders
#   5. Generates a migration report with counts, sizes, and upload instructions
#
# Prerequisites:
#   1. macOS with Homebrew installed
#   2. Python 3 (installed via Homebrew)
#   3. Google Takeout export(s) - all zips unzipped into one folder
#   4. Proton Drive desktop app installed (optional, for path detection)
#
# Usage: ./google_photos_migration.sh
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

################################################################################
# Step 1: Check Prerequisites
################################################################################
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if on macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_error "This script is designed for macOS only"
        exit 1
    fi
    log_success "Running on macOS"
    
    # Check Homebrew
    if ! command -v brew &> /dev/null; then
        log_error "Homebrew not found. Install from https://brew.sh"
        exit 1
    fi
    log_success "Homebrew found"
    
    # Check Python 3
    if ! command -v python3 &> /dev/null; then
        log_warning "Python 3 not found. Installing via Homebrew..."
        brew install python3
    fi
    log_success "Python 3 found"
    
    # Check exiftool (needed for metadata handling)
    if ! command -v exiftool &> /dev/null; then
        log_warning "exiftool not found. Installing via Homebrew..."
        brew install exiftool
    fi
    log_success "exiftool found"
    
    # Install jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq not found. Installing via Homebrew..."
        brew install jq
    fi
    log_success "jq found"
}

################################################################################
# Step 2: Get Paths from User
################################################################################
get_user_paths() {
    log_info "Setting up migration paths..."
    
    # Input Takeout folder (can contain multiple merged Takeout exports)
    echo ""
    echo "Your Takeout folder should contain unzipped Google Takeout exports."
    echo "Example structure: /path/to/GoogleTakeoutMerged/Takeout 1/Google Photos/..."
    echo "                   /path/to/GoogleTakeoutMerged/Takeout 2/Google Photos/..."
    echo ""
    read -p "Enter path to your merged Google Takeout folder: " TAKEOUT_INPUT
    TAKEOUT_INPUT="${TAKEOUT_INPUT/#\~/$HOME}"
    # Remove trailing slash if present
    TAKEOUT_INPUT="${TAKEOUT_INPUT%/}"
    
    if [ ! -d "$TAKEOUT_INPUT" ]; then
        log_error "Takeout folder not found at: $TAKEOUT_INPUT"
        exit 1
    fi
    
    # Verify it looks like a Takeout export
    if ! find "$TAKEOUT_INPUT" -type d -name "Google Photos" -print -quit | grep -q .; then
        log_warning "No 'Google Photos' subfolder found. Make sure this is a valid Takeout export."
        read -p "Continue anyway? (y/n): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    log_success "Takeout folder found: $TAKEOUT_INPUT"
    
    # Count input files
    INPUT_COUNT=$(find "$TAKEOUT_INPUT" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" \) 2>/dev/null | wc -l | tr -d ' ')
    log_info "Found approximately $INPUT_COUNT media files in source"
    
    # Output folder for processed photos
    echo ""
    read -p "Enter path for output folder (will be created if doesn't exist): " OUTPUT_FOLDER
    OUTPUT_FOLDER="${OUTPUT_FOLDER/#\~/$HOME}"
    OUTPUT_FOLDER="${OUTPUT_FOLDER%/}"
    
    if [ -d "$OUTPUT_FOLDER" ] && [ "$(ls -A "$OUTPUT_FOLDER" 2>/dev/null)" ]; then
        log_warning "Output folder exists and is not empty: $OUTPUT_FOLDER"
        read -p "Continue and potentially overwrite? (y/n): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    mkdir -p "$OUTPUT_FOLDER"
    log_success "Output folder ready: $OUTPUT_FOLDER"
}

################################################################################
# Step 3: Download and Setup GooglePhotosTakeoutHelper
################################################################################
setup_takeout_helper() {
    log_info "Setting up GooglePhotosTakeoutHelper..."
    
    HELPER_DIR="$HOME/.google_photos_helper"
    mkdir -p "$HELPER_DIR"
    
    # Install via pip
    if ! python3 -c "import google_photos_takeout_helper" 2>/dev/null; then
        log_info "Installing google-photos-takeout-helper via pip..."
        python3 -m pip install --upgrade google-photos-takeout-helper --quiet
    fi
    
    log_success "GooglePhotosTakeoutHelper ready"
}

################################################################################
# Helper: Check if a file is a Live Photo video component
################################################################################
is_live_photo_video() {
    local video_file="$1"
    local search_dir="$2"
    local filename=$(basename "$video_file")
    local base_name="${filename%.*}"
    local ext_lower=$(echo "${filename##*.}" | tr '[:upper:]' '[:lower:]')
    
    # Only check MOV files - Live Photos are almost always MOV format
    if [[ "$ext_lower" != "mov" ]]; then
        return 1
    fi
    
    # Live Photos are typically very short (1-3 seconds) and small
    # Check file size - Live Photo videos are usually under 5MB
    local file_size=$(stat -f%z "$video_file" 2>/dev/null || stat -c%s "$video_file" 2>/dev/null)
    if [ -n "$file_size" ] && [ "$file_size" -gt 5000000 ]; then
        return 1  # Too big to be a Live Photo - keep it
    fi
    
    # Check if there's a matching HEIC file (Live Photos are iPhone feature)
    # Only consider it a Live Photo if there's a HEIC with exact same name
    if [ -f "$search_dir/${base_name}.HEIC" ] || [ -f "$search_dir/${base_name}.heic" ]; then
        # Additional check: Live Photo videos are usually under 3 seconds
        local duration=$(get_video_duration "$video_file")
        local int_duration=$(echo "$duration" | cut -d. -f1)
        if [ -n "$int_duration" ] && [ "$int_duration" -le 3 ] 2>/dev/null; then
            return 0  # This IS a Live Photo video
        fi
    fi
    
    return 1  # Not a Live Photo video
}

################################################################################
# Helper: Get video duration in seconds
################################################################################
get_video_duration() {
    local video_file="$1"
    local duration=""
    
    # Try to get duration using exiftool (most reliable for various formats)
    duration=$(exiftool -Duration -s3 "$video_file" 2>/dev/null | grep -oE '^[0-9]+\.?[0-9]*' | head -1)
    
    # If duration is in HH:MM:SS format, convert to seconds
    if [ -z "$duration" ]; then
        local time_str=$(exiftool -Duration -s3 "$video_file" 2>/dev/null)
        if [[ "$time_str" =~ ([0-9]+):([0-9]+):([0-9]+) ]]; then
            duration=$(( ${BASH_REMATCH[1]} * 3600 + ${BASH_REMATCH[2]} * 60 + ${BASH_REMATCH[3]} ))
        elif [[ "$time_str" =~ ([0-9]+):([0-9]+) ]]; then
            duration=$(( ${BASH_REMATCH[1]} * 60 + ${BASH_REMATCH[2]} ))
        elif [[ "$time_str" =~ ([0-9]+\.?[0-9]*)\ *s ]]; then
            duration="${BASH_REMATCH[1]}"
        fi
    fi
    
    # Fallback: try ffprobe if available
    if [ -z "$duration" ] || [ "$duration" = "0" ]; then
        if command -v ffprobe &> /dev/null; then
            duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null | cut -d. -f1)
        fi
    fi
    
    # Return empty if we couldn't determine duration (will keep the file)
    echo "${duration:-}"
}

################################################################################
# Helper: Check if file should be kept (not Live Photo, videos >= 5 sec)
# CONSERVATIVE: When in doubt, KEEP the file
################################################################################
should_keep_file() {
    local file="$1"
    local search_dir="$2"
    local filename=$(basename "$file")
    local ext_lower=$(echo "${filename##*.}" | tr '[:upper:]' '[:lower:]')
    
    # Always keep still images
    if [[ "$ext_lower" =~ ^(jpg|jpeg|png|heic|gif|webp|bmp|tiff|tif)$ ]]; then
        return 0  # Keep
    fi
    
    # For videos, be CONSERVATIVE - keep unless we're sure it's a Live Photo
    if [[ "$ext_lower" =~ ^(mov|mp4|m4v|avi|mkv|3gp)$ ]]; then
        # Only filter out if it's definitely a Live Photo video
        if is_live_photo_video "$file" "$search_dir"; then
            return 1  # Don't keep - it's a Live Photo video
        fi
        
        # For all other videos: KEEP THEM
        # We no longer filter by duration - user wants to keep all videos
        return 0  # Keep the video
    fi
    
    # Keep unknown formats too - let user decide
    return 0
}

################################################################################
# Step 4: Process Photos with Metadata Merge
################################################################################
process_photos_with_metadata() {
    # Set global variables
    PROCESSED_FOLDER="$OUTPUT_FOLDER/ALL_PHOTOS"
    ALBUMS_FOLDER="$OUTPUT_FOLDER/ALBUMS"
    mkdir -p "$PROCESSED_FOLDER"
    mkdir -p "$ALBUMS_FOLDER"
    
    log_info "Processing photos and merging metadata..."
    log_info "This may take a while depending on library size..."
    log_info "Filtering: Only removing confirmed Live Photo videos (MOV paired with HEIC, <3 sec)"
    echo ""
    
    # We'll process the photos ourselves since google-photos-takeout-helper
    # is too picky about folder naming formats.
    
    local TOTAL_COPIED=0
    local TOTAL_ALBUMS=0
    local TOTAL_DATE_PHOTOS=0
    local LIVE_PHOTOS_SKIPPED=0
    
    # Track all files added to ALL_PHOTOS for album validation
    ALL_PHOTOS_HASHES_FILE=$(mktemp)
    
    # PHASE 1: First, collect ALL photos from ALL folders into ALL_PHOTOS
    # This ensures every photo exists in ALL_PHOTOS organized by year
    log_info "Phase 1: Collecting ALL photos into ALL_PHOTOS (by year)..."
    
    # Find all Google Photos directories
    while IFS= read -r google_photos_dir; do
        log_info "Processing: $google_photos_dir"
        
        # Process each subfolder (both date folders AND album folders)
        for subfolder in "$google_photos_dir"/*/; do
            if [ -d "$subfolder" ]; then
                folder_name=$(basename "$subfolder")
                
                # Skip certain system folders
                if [[ "$folder_name" == "Untitled"* ]] || [[ "$folder_name" == "Failed"* ]]; then
                    continue
                fi
                
                # Determine year for this folder
                local YEAR=""
                if [[ "$folder_name" =~ ^Photos\ from\ ([0-9]{4})$ ]]; then
                    YEAR="${BASH_REMATCH[1]}"
                    log_info "  📅 Date folder: $folder_name"
                else
                    # Album folder - we'll extract year from each file's JSON or EXIF
                    log_info "  📁 Album folder: $folder_name (extracting to ALL_PHOTOS)"
                fi
                
                # Copy all media files to ALL_PHOTOS
                for file in "$subfolder"/*; do
                    if [ -f "$file" ]; then
                        filename=$(basename "$file")
                        extension="${filename##*.}"
                        ext_lower=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
                            
                        # Skip JSON files and other non-media
                        if [[ "$ext_lower" =~ ^(jpg|jpeg|png|heic|gif|mp4|mov|avi|mkv|webp|bmp|tiff|tif|3gp|m4v)$ ]]; then
                            # Check if we should keep this file (only filters Live Photos)
                            if ! should_keep_file "$file" "$subfolder"; then
                                # Only Live Photos get filtered now
                                ((LIVE_PHOTOS_SKIPPED++)) || true
                                continue
                            fi
                            
                            # Determine year if not already set (for album folders)
                            local FILE_YEAR="$YEAR"
                            if [ -z "$FILE_YEAR" ]; then
                                # Try to get year from JSON sidecar
                                local base_name="${filename%.*}"
                                local json_file=""
                                for json_path in "$subfolder/${filename}.json" "$subfolder/${base_name}.json"; do
                                    if [ -f "$json_path" ]; then
                                        json_file="$json_path"
                                        break
                                    fi
                                done
                                
                                if [ -n "$json_file" ]; then
                                    local timestamp=$(jq -r '.photoTakenTime.timestamp // .creationTime.timestamp // empty' "$json_file" 2>/dev/null)
                                    if [ -n "$timestamp" ] && [ "$timestamp" != "null" ]; then
                                        FILE_YEAR=$(date -r "$timestamp" "+%Y" 2>/dev/null)
                                    fi
                                fi
                                
                                # Fallback: try EXIF
                                if [ -z "$FILE_YEAR" ]; then
                                    FILE_YEAR=$(exiftool -DateTimeOriginal -s3 "$file" 2>/dev/null | cut -d: -f1)
                                fi
                                
                                # Final fallback: use current year
                                if [ -z "$FILE_YEAR" ] || ! [[ "$FILE_YEAR" =~ ^[0-9]{4}$ ]]; then
                                    FILE_YEAR="Unknown"
                                fi
                            fi
                            
                            # Create year folder and copy
                            mkdir -p "$PROCESSED_FOLDER/$FILE_YEAR"
                            
                            # Check if file already exists, add suffix if needed
                            dest="$PROCESSED_FOLDER/$FILE_YEAR/$filename"
                            if [ -f "$dest" ]; then
                                # Check if it's the same file (by hash)
                                local new_hash=$(md5 -q "$file" 2>/dev/null)
                                local existing_hash=$(md5 -q "$dest" 2>/dev/null)
                                if [ "$new_hash" = "$existing_hash" ]; then
                                    continue  # Skip duplicate
                                fi
                                base="${filename%.*}"
                                dest="$PROCESSED_FOLDER/$FILE_YEAR/${base}_$(date +%s%N | cut -c1-13).${extension}"
                            fi
                            
                            cp -p "$file" "$dest" 2>/dev/null && ((TOTAL_DATE_PHOTOS++)) || true
                            
                            # Track file hash for album validation
                            echo "$(md5 -q "$dest" 2>/dev/null)" >> "$ALL_PHOTOS_HASHES_FILE"
                        fi
                    fi
                done
            fi
        done
    done < <(find "$TAKEOUT_INPUT" -type d -name "Google Photos" 2>/dev/null)
    
    echo ""
    log_success "Copied $TOTAL_DATE_PHOTOS photos/videos to ALL_PHOTOS (by year)"
    if [ "$LIVE_PHOTOS_SKIPPED" -gt 0 ]; then
        log_info "Skipped $LIVE_PHOTOS_SKIPPED Live Photo videos (MOV paired with HEIC)"
    fi
    
    # PHASE 2: Now create album structure that references ALL_PHOTOS
    log_info ""
    log_info "Phase 2: Creating album structure..."
    
    # Process albums again, but this time only create references
    while IFS= read -r google_photos_dir; do
        for subfolder in "$google_photos_dir"/*/; do
            if [ -d "$subfolder" ]; then
                folder_name=$(basename "$subfolder")
                
                # Skip date folders and system folders
                if [[ "$folder_name" =~ ^Photos\ from\ [0-9]{4}$ ]]; then
                    continue
                fi
                if [[ "$folder_name" == "Untitled"* ]] || [[ "$folder_name" == "Failed"* ]]; then
                    continue
                fi
                
                log_info "  📁 Album: $folder_name"
                ((TOTAL_ALBUMS++)) || true
                
                mkdir -p "$ALBUMS_FOLDER/$folder_name"
                
                # Copy album photos (these should already exist in ALL_PHOTOS)
                for file in "$subfolder"/*; do
                    if [ -f "$file" ]; then
                        filename=$(basename "$file")
                        extension="${filename##*.}"
                        ext_lower=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
                        
                        if [[ "$ext_lower" =~ ^(jpg|jpeg|png|heic|gif|mp4|mov|avi|mkv|webp|bmp|tiff|tif|3gp|m4v)$ ]]; then
                            # Check if we should keep this file
                            if ! should_keep_file "$file" "$subfolder"; then
                                continue
                            fi
                            
                            dest="$ALBUMS_FOLDER/$folder_name/$filename"
                            if [ ! -f "$dest" ]; then
                                cp -p "$file" "$dest" 2>/dev/null && ((TOTAL_COPIED++)) || true
                            fi
                        fi
                    fi
                done
            fi
        done
    done < <(find "$TAKEOUT_INPUT" -type d -name "Google Photos" 2>/dev/null)
    
    log_success "Created $TOTAL_ALBUMS album folders"
    
    # Clean up temp file
    rm -f "$ALL_PHOTOS_HASHES_FILE"
    
    # Now fix metadata using JSON sidecars
    log_info ""
    log_info "Fixing metadata from JSON sidecars..."
    fix_all_metadata
    
    # Validate album photos exist in ALL_PHOTOS
    log_info ""
    validate_album_photos
}

################################################################################
# Step 4b: Validate Album Photos Exist in ALL_PHOTOS
##########################################################################![1767898302373](image/google_photos_migration/1767898302373.png)![1767898309977](image/google_photos_migration/1767898309977.png)![1767898310749](image/google_photos_migration/1767898310749.png)######
validate_album_photos() {
    log_info "Validating all album photos exist in ALL_PHOTOS..."
    
    local MISSING_COUNT=0
    local FOUND_COUNT=0
    local TOTAL_ALBUM_FILES=0
    
    # Build hash index of ALL_PHOTOS
    log_info "Building ALL_PHOTOS index..."
    declare -A ALL_PHOTOS_INDEX
    
    while IFS= read -r photo; do
        local hash=$(md5 -q "$photo" 2>/dev/null)
        if [ -n "$hash" ]; then
            ALL_PHOTOS_INDEX["$hash"]="$photo"
        fi
    done < <(find "$PROCESSED_FOLDER" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.m4v" -o -iname "*.3gp" -o -iname "*.webp" -o -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.tif" \) 2>/dev/null)
    
    log_info "Checking album files..."
    
    # Check each album file
    while IFS= read -r album_photo; do
        ((TOTAL_ALBUM_FILES++)) || true
        
        local hash=$(md5 -q "$album_photo" 2>/dev/null)
        local filename=$(basename "$album_photo")
        
        if [ -n "${ALL_PHOTOS_INDEX[$hash]+x}" ]; then
            ((FOUND_COUNT++)) || true
        else
            # Photo not in ALL_PHOTOS - need to add it
            ((MISSING_COUNT++)) || true
            
            # Try to determine year and add to ALL_PHOTOS
            local FILE_YEAR="Unknown"
            local album_dir=$(dirname "$album_photo")
            local base_name="${filename%.*}"
            
            # Try JSON sidecar from original takeout
            while IFS= read -r json_file; do
                if [ -f "$json_file" ]; then
                    local timestamp=$(jq -r '.photoTakenTime.timestamp // .creationTime.timestamp // empty' "$json_file" 2>/dev/null)
                    if [ -n "$timestamp" ] && [ "$timestamp" != "null" ]; then
                        FILE_YEAR=$(date -r "$timestamp" "+%Y" 2>/dev/null)
                        break
                    fi
                fi
            done < <(find "$TAKEOUT_INPUT" \( -name "${filename}.json" -o -name "${base_name}.json" \) -type f 2>/dev/null | head -2)
            
            # Fallback: EXIF
            if [ "$FILE_YEAR" = "Unknown" ] || ! [[ "$FILE_YEAR" =~ ^[0-9]{4}$ ]]; then
                FILE_YEAR=$(exiftool -DateTimeOriginal -s3 "$album_photo" 2>/dev/null | cut -d: -f1)
            fi
            
            if [ -z "$FILE_YEAR" ] || ! [[ "$FILE_YEAR" =~ ^[0-9]{4}$ ]]; then
                FILE_YEAR="Unknown"
            fi
            
            # Copy to ALL_PHOTOS
            mkdir -p "$PROCESSED_FOLDER/$FILE_YEAR"
            local dest="$PROCESSED_FOLDER/$FILE_YEAR/$filename"
            if [ -f "$dest" ]; then
                local extension="${filename##*.}"
                base_name="${filename%.*}"
                dest="$PROCESSED_FOLDER/$FILE_YEAR/${base_name}_$(date +%s%N | cut -c1-13).${extension}"
            fi
            cp -p "$album_photo" "$dest" 2>/dev/null
            log_info "  Added missing: $filename -> ALL_PHOTOS/$FILE_YEAR/"
        fi
        
        if [ $((TOTAL_ALBUM_FILES % 100)) -eq 0 ]; then
            echo -ne "\r  Validated $TOTAL_ALBUM_FILES album files..."
        fi
    done < <(find "$ALBUMS_FOLDER" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.m4v" -o -iname "*.3gp" -o -iname "*.webp" -o -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.tif" \) 2>/dev/null)
    
    echo ""
    log_success "Album validation complete: $FOUND_COUNT files already in ALL_PHOTOS"
    if [ "$MISSING_COUNT" -gt 0 ]; then
        log_success "Added $MISSING_COUNT missing files to ALL_PHOTOS"
    fi
    log_info "All album photos are now guaranteed to exist in ALL_PHOTOS!"
}

################################################################################
# Step 4c: Fix Metadata for All Photos using JSON sidecars
################################################################################
fix_all_metadata() {
    log_info "Applying metadata from JSON sidecars to all photos and videos..."
    echo ""
    
    local FIXED_COUNT=0
    local TOTAL_COUNT=0
    local FAILED_COUNT=0
    
    # Process ALL_PHOTOS (photos AND videos)
    log_info "Processing ALL_PHOTOS..."
    while IFS= read -r photo; do
        ((TOTAL_COUNT++)) || true
        if fix_single_photo_metadata "$photo"; then
            ((FIXED_COUNT++)) || true
        fi
        
        # Progress indicator every 100 files
        if [ $((TOTAL_COUNT % 100)) -eq 0 ]; then
            echo -ne "\r  Processed $TOTAL_COUNT files..."
        fi
    done < <(find "$PROCESSED_FOLDER" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.m4v" -o -iname "*.3gp" \) 2>/dev/null)
    echo ""
    
    # Process ALBUMS (photos AND videos)
    log_info "Processing ALBUMS..."
    local ALBUM_TOTAL=0
    local ALBUM_FIXED=0
    while IFS= read -r photo; do
        ((ALBUM_TOTAL++)) || true
        if fix_single_photo_metadata "$photo"; then
            ((ALBUM_FIXED++)) || true
        fi
        
        if [ $((ALBUM_TOTAL % 100)) -eq 0 ]; then
            echo -ne "\r  Processed $ALBUM_TOTAL album files..."
        fi
    done < <(find "$ALBUMS_FOLDER" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.m4v" -o -iname "*.3gp" \) 2>/dev/null)
    echo ""
    
    log_success "Fixed metadata for $FIXED_COUNT of $TOTAL_COUNT files in ALL_PHOTOS"
    log_success "Fixed metadata for $ALBUM_FIXED of $ALBUM_TOTAL files in ALBUMS"
    
    # Final pass: sync file modification dates from EXIF for any files that might have been missed
    log_info "Final pass: syncing file dates from EXIF metadata..."
    sync_file_dates_from_exif
}

# Helper function to fix metadata for a single photo or video
fix_single_photo_metadata() {
    local photo="$1"
    local filename=$(basename "$photo")
    local found_json=""
    local extension="${filename##*.}"
    local ext_lower=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
    
    # Determine if this is a video file
    local IS_VIDEO=0
    if [[ "$ext_lower" =~ ^(mp4|mov|avi|mkv|m4v|3gp)$ ]]; then
        IS_VIDEO=1
    fi
    
    # Try to find the JSON sidecar in the original Takeout
    # Google uses various naming patterns for JSON files
    
    # Pattern 1: filename.json (e.g., IMG_1234.jpg.json)
    # Pattern 2: filename without extension.json (e.g., IMG_1234.json)
    # Pattern 3: truncated filename.json for long names
    
    local base_name="${filename%.*}"
    
    # Search for matching JSON in Takeout
    while IFS= read -r potential_json; do
        if [ -f "$potential_json" ]; then
            found_json="$potential_json"
            break
        fi
    done < <(find "$TAKEOUT_INPUT" \( -name "${filename}.json" -o -name "${base_name}.json" -o -name "${base_name}.*.json" \) -type f 2>/dev/null | head -3)
    
    if [ -z "$found_json" ]; then
        # Try a more fuzzy match for truncated filenames
        local short_name="${base_name:0:46}"
        while IFS= read -r potential_json; do
            if [ -f "$potential_json" ]; then
                found_json="$potential_json"
                break
            fi
        done < <(find "$TAKEOUT_INPUT" -name "${short_name}*.json" -type f 2>/dev/null | head -1)
    fi
    
    if [ -n "$found_json" ] && [ -f "$found_json" ]; then
        # Extract timestamp from JSON
        local TIMESTAMP=$(jq -r '.photoTakenTime.timestamp // .creationTime.timestamp // empty' "$found_json" 2>/dev/null)
        
        if [ -n "$TIMESTAMP" ] && [ "$TIMESTAMP" != "null" ] && [ "$TIMESTAMP" != "" ]; then
            # Convert Unix timestamp to exiftool format
            local DATETIME=$(date -r "$TIMESTAMP" "+%Y:%m:%d %H:%M:%S" 2>/dev/null)
            local TOUCH_DATE=$(date -r "$TIMESTAMP" "+%Y%m%d%H%M.%S" 2>/dev/null)
            
            if [ -n "$DATETIME" ]; then
                if [ $IS_VIDEO -eq 1 ]; then
                    # For videos, set video-specific date fields
                    exiftool -overwrite_original -q \
                        -CreateDate="$DATETIME" \
                        -ModifyDate="$DATETIME" \
                        -MediaCreateDate="$DATETIME" \
                        -MediaModifyDate="$DATETIME" \
                        -TrackCreateDate="$DATETIME" \
                        -TrackModifyDate="$DATETIME" \
                        "$photo" 2>/dev/null || true
                else
                    # For photos, set photo date fields
                    exiftool -overwrite_original -q \
                        -DateTimeOriginal="$DATETIME" \
                        -CreateDate="$DATETIME" \
                        -ModifyDate="$DATETIME" \
                        "$photo" 2>/dev/null
                    
                    # Extract and apply GPS data if available (photos only)
                    local LAT=$(jq -r '.geoData.latitude // .geoDataExif.latitude // empty' "$found_json" 2>/dev/null)
                    local LON=$(jq -r '.geoData.longitude // .geoDataExif.longitude // empty' "$found_json" 2>/dev/null)
                    
                    if [ -n "$LAT" ] && [ -n "$LON" ] && [ "$LAT" != "0.0" ] && [ "$LON" != "0.0" ] && [ "$LAT" != "0" ] && [ "$LON" != "0" ]; then
                        exiftool -overwrite_original -q \
                            -GPSLatitude="$LAT" \
                            -GPSLongitude="$LON" \
                            -GPSLatitudeRef="$(echo "$LAT" | grep -q '^-' && echo 'S' || echo 'N')" \
                            -GPSLongitudeRef="$(echo "$LON" | grep -q '^-' && echo 'W' || echo 'E')" \
                            "$photo" 2>/dev/null || true
                    fi
                fi
                
                # IMPORTANT: Set file modification time AFTER all exiftool operations
                # (exiftool -overwrite_original resets the file modification time)
                touch -t "$TOUCH_DATE" "$photo" 2>/dev/null
                
                return 0
            fi
        fi
    fi
    
    return 1
}

################################################################################
# Step 4d: Sync File Dates from EXIF (safety net)
################################################################################
sync_file_dates_from_exif() {
    log_info "Syncing file modification dates from EXIF for all media..."
    
    # Use exiftool to set FileModifyDate from EXIF dates
    # This handles cases where touch command failed or was overwritten
    # The order of preference: DateTimeOriginal > CreateDate > MediaCreateDate
    
    exiftool -overwrite_original -r -q \
        '-FileModifyDate<DateTimeOriginal' \
        '-FileModifyDate<CreateDate' \
        '-FileModifyDate<MediaCreateDate' \
        "$PROCESSED_FOLDER" "$ALBUMS_FOLDER" 2>/dev/null || true
    
    # Fix remaining files using folder year as fallback
    log_info "Fixing remaining files using folder year..."
    local FIXED_FROM_FOLDER=0
    
    # Process ALL_PHOTOS by year folder
    for year_folder in "$PROCESSED_FOLDER"/*/; do
        if [ -d "$year_folder" ]; then
            local YEAR=$(basename "$year_folder")
            # Only process if it looks like a year (4 digits)
            if [[ "$YEAR" =~ ^[0-9]{4}$ ]]; then
                # Find files in this year folder with recent modification dates
                while IFS= read -r -d '' file; do
                    # Check if file has recent modification date (2026)
                    if [ "$(stat -f "%Sm" -t "%Y" "$file" 2>/dev/null)" = "2026" ]; then
                        # Set file date to mid-year of the folder year
                        touch -t "${YEAR}0701120000.00" "$file" 2>/dev/null && ((FIXED_FROM_FOLDER++)) || true
                    fi
                done < <(find "$year_folder" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mov" \) -print0 2>/dev/null)
            fi
        fi
    done
    
    if [ "$FIXED_FROM_FOLDER" -gt 0 ]; then
        log_success "Fixed $FIXED_FROM_FOLDER files using folder year as fallback"
    fi
    
    # Count any remaining files with recent dates (potential issues)
    local REMAINING=$(find "$OUTPUT_FOLDER" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mov" \) -newermt "$(date +%Y)-01-01" 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$REMAINING" -gt 50 ]; then
        log_warning "$REMAINING files still have recent dates - some may be missing EXIF data"
    else
        log_success "File dates synced successfully (only $REMAINING current-year files remain)"
    fi
}

################################################################################
# Step 5: De-duplicate Photos
################################################################################
deduplicate_photos() {
    local FOLDER=$1
    
    log_info "Checking for duplicate files..."
    
    DUPE_LOG="$OUTPUT_FOLDER/duplicates.log"
    DUPE_COUNT=0
    
    # Use a simple hash-based deduplication
    # Create a temp file to track hashes
    HASH_FILE=$(mktemp)
    
    while IFS= read -r -d '' file; do
        # Get file hash (using first 100KB for speed on large files)
        HASH=$(head -c 102400 "$file" 2>/dev/null | md5 -q 2>/dev/null || head -c 102400 "$file" | md5sum | cut -d' ' -f1)
        SIZE=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        KEY="${HASH}_${SIZE}"
        
        if grep -q "^$KEY$" "$HASH_FILE" 2>/dev/null; then
            echo "Duplicate: $file" >> "$DUPE_LOG"
            rm "$file"
            ((DUPE_COUNT++)) || true
        else
            echo "$KEY" >> "$HASH_FILE"
        fi
    done < <(find "$FOLDER" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mov" \) -print0 2>/dev/null)
    
    rm -f "$HASH_FILE"
    
    if [ $DUPE_COUNT -gt 0 ]; then
        log_success "Removed $DUPE_COUNT duplicate files (see duplicates.log)"
    else
        log_success "No duplicates found"
    fi
}

################################################################################
# Step 6: Organize and Clean Album Structure  
################################################################################
organize_albums() {
    log_info "Organizing final structure..."
    
    # Remove empty directories from processed output
    find "$PROCESSED_FOLDER" -type d -empty -delete 2>/dev/null || true
    find "$ALBUMS_FOLDER" -type d -empty -delete 2>/dev/null || true
    
    # Count what we have in ALL_PHOTOS
    TOTAL_FILES=$(find "$PROCESSED_FOLDER" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mov" \) 2>/dev/null | wc -l | tr -d ' ')
    
    # Count albums
    ALBUM_COUNT=$(find "$ALBUMS_FOLDER" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    ALBUM_FILES=$(find "$ALBUMS_FOLDER" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mov" \) 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$TOTAL_FILES" -eq 0 ] && [ "$ALBUM_FILES" -eq 0 ]; then
        log_warning "No media files found in output!"
        log_info "This could mean:"
        echo "  - The Takeout folder structure wasn't recognized"
        echo "  - Photos are in an unexpected location"
        return 1
    fi
    
    log_success "Found $TOTAL_FILES files in ALL_PHOTOS"
    log_success "Found $ALBUM_FILES files in $ALBUM_COUNT albums"
    
    # List date folders in ALL_PHOTOS
    if [ "$TOTAL_FILES" -gt 0 ]; then
        echo ""
        log_info "Date folders in ALL_PHOTOS:"
        for folder in "$PROCESSED_FOLDER"/*/; do
            if [ -d "$folder" ]; then
                folder_name=$(basename "$folder")
                photo_count=$(find "$folder" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mov" \) 2>/dev/null | wc -l | tr -d ' ')
                echo "   📅 $folder_name ($photo_count files)"
            fi
        done
    fi
    
    # List albums
    if [ "$ALBUM_COUNT" -gt 0 ]; then
        echo ""
        log_info "Albums preserved:"
        for album in "$ALBUMS_FOLDER"/*/; do
            if [ -d "$album" ]; then
                album_name=$(basename "$album")
                photo_count=$(find "$album" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mov" \) 2>/dev/null | wc -l | tr -d ' ')
                echo "   � $album_name ($photo_count files)"
            fi
        done
    fi
    
    log_success "Organization complete"
}

################################################################################
# Step 7: Verify Metadata
################################################################################
verify_metadata() {
    local FOLDER=$1
    
    log_info "Verifying metadata in processed photos..."
    
    # Find a few sample photos
    SAMPLE_PHOTOS=$(find "$FOLDER" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" \) 2>/dev/null | head -3)
    
    if [ -z "$SAMPLE_PHOTOS" ]; then
        log_warning "No photos found to verify"
        return
    fi
    
    SAMPLE_PHOTO=$(echo "$SAMPLE_PHOTOS" | head -1)
    
    echo ""
    log_info "Sample photo: $(basename "$SAMPLE_PHOTO")"
    echo "─────────────────────────────────────────────────"
    
    # Show key metadata fields
    exiftool -DateTimeOriginal -CreateDate -ModifyDate -GPSLatitude -GPSLongitude -ImageDescription "$SAMPLE_PHOTO" 2>/dev/null | head -10
    
    echo "─────────────────────────────────────────────────"
    
    # Check if dates are set
    DATE_CHECK=$(exiftool -DateTimeOriginal -s3 "$SAMPLE_PHOTO" 2>/dev/null)
    if [ -n "$DATE_CHECK" ] && [ "$DATE_CHECK" != "-" ]; then
        log_success "✓ DateTimeOriginal is set: $DATE_CHECK"
    else
        log_warning "⚠ DateTimeOriginal not found in sample"
    fi
    
    # Check file modification time
    FILE_DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$SAMPLE_PHOTO" 2>/dev/null || stat -c "%y" "$SAMPLE_PHOTO" 2>/dev/null | cut -d'.' -f1)
    log_info "File modification time: $FILE_DATE"
    
    log_success "Metadata verification complete"
}

################################################################################
# Step 8: Generate Migration Report
################################################################################
generate_report() {
    local REPORT_FILE="$OUTPUT_FOLDER/MIGRATION_REPORT.txt"
    
    log_info "Generating migration report..."
    
    # Calculate statistics
    TOTAL_PHOTOS=$(find "$PROCESSED_FOLDER" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.gif" \) 2>/dev/null | wc -l | tr -d ' ')
    TOTAL_VIDEOS=$(find "$PROCESSED_FOLDER" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" \) 2>/dev/null | wc -l | tr -d ' ')
    TOTAL_SIZE=$(du -sh "$PROCESSED_FOLDER" 2>/dev/null | cut -f1)
    DATE_FOLDERS=$(find "$PROCESSED_FOLDER" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    ALBUM_COUNT=$(find "$ALBUMS_FOLDER" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    ALBUM_SIZE=$(du -sh "$ALBUMS_FOLDER" 2>/dev/null | cut -f1)
    
    {
        echo "════════════════════════════════════════════════════════════"
        echo "  GOOGLE PHOTOS → PROTON DRIVE MIGRATION REPORT"
        echo "════════════════════════════════════════════════════════════"
        echo ""
        echo "Generated: $(date)"
        echo ""
        echo "┌─────────────────────────────────────────────────────────┐"
        echo "│  PATHS                                                   │"
        echo "├─────────────────────────────────────────────────────────┤"
        echo "│  Source (Takeout):  $TAKEOUT_INPUT"
        echo "│  ALL_PHOTOS:        $PROCESSED_FOLDER"
        echo "│  ALBUMS:            $ALBUMS_FOLDER"
        echo "└─────────────────────────────────────────────────────────┘"
        echo ""
        echo "┌─────────────────────────────────────────────────────────┐"
        echo "│  STATISTICS                                              │"
        echo "├─────────────────────────────────────────────────────────┤"
        echo "│  Photos:        $TOTAL_PHOTOS files"
        echo "│  Videos:        $TOTAL_VIDEOS files"
        echo "│  Total:         $((TOTAL_PHOTOS + TOTAL_VIDEOS)) media files"
        echo "│  Total Size:    $TOTAL_SIZE"
        echo "│  Date Folders:  $DATE_FOLDERS"
        echo "│  Albums:        $ALBUM_COUNT ($ALBUM_SIZE)"
        echo "└─────────────────────────────────────────────────────────┘"
        echo ""
        echo "┌─────────────────────────────────────────────────────────┐"
        echo "│  DATE FOLDERS                                            │"
        echo "├─────────────────────────────────────────────────────────┤"
        for folder in "$PROCESSED_FOLDER"/*/; do
            if [ -d "$folder" ]; then
                folder_name=$(basename "$folder")
                photo_count=$(find "$folder" -type f 2>/dev/null | wc -l | tr -d ' ')
                printf "│  📅 %-40s %5s files │\n" "$folder_name" "$photo_count"
            fi
        done
        echo "└─────────────────────────────────────────────────────────┘"
        echo ""
        if [ "$ALBUM_COUNT" -gt 0 ]; then
            echo "┌─────────────────────────────────────────────────────────┐"
            echo "│  ALBUMS                                                  │"
            echo "├─────────────────────────────────────────────────────────┤"
            for album in "$ALBUMS_FOLDER"/*/; do
                if [ -d "$album" ]; then
                    album_name=$(basename "$album")
                    photo_count=$(find "$album" -type f 2>/dev/null | wc -l | tr -d ' ')
                    printf "│  � %-40s %5s files │\n" "$album_name" "$photo_count"
                fi
            done
            echo "└─────────────────────────────────────────────────────────┘"
            echo ""
        fi
        echo "┌─────────────────────────────────────────────────────────┐"
        echo "│  WHAT WAS DONE                                           │"
        echo "├─────────────────────────────────────────────────────────┤"
        echo "│  ✓ JSON metadata merged into file EXIF                   │"
        echo "│  ✓ DateTimeOriginal set from Google's timestamp          │"
        echo "│  ✓ File modification times corrected                     │"
        echo "│  ✓ GPS coordinates preserved (where available)           │"
        echo "│  ✓ Live Photo videos removed (MOV paired with HEIC)      │"
        echo "│  ✓ Duplicates removed                                    │"
        echo "│  ✓ Photos organized by date                              │"
        echo "│  ✓ Album photos validated in ALL_PHOTOS                  │"
        echo "└─────────────────────────────────────────────────────────┘"
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo "  HOW TO UPLOAD TO PROTON DRIVE"
        echo "════════════════════════════════════════════════════════════"
        echo ""
        echo "STEPS:"
        echo "──────────────────────────────────────────────────────────"
        echo "  1. Open Proton Drive app or web (drive.proton.me)"
        echo "  2. Go to the 'Photos' section"
        echo "  3. Drag the contents of ALL_PHOTOS into the Photos area"
        echo "  4. Proton will organize by date automatically using EXIF"
        echo ""
        echo "TO CREATE ALBUMS IN PROTON DRIVE:"
        echo "──────────────────────────────────────────────────────────"
        echo "  1. Upload ALL_PHOTOS first (main timeline)"
        echo "  2. In Proton Drive Photos, create new albums"
        echo "  3. Upload the ALBUMS folder contents to match"
        echo "  4. Or: select photos already uploaded and add to albums"
        echo ""
        echo "OUTPUT FOLDERS ON YOUR MAC:"
        echo "  ALL_PHOTOS: $PROCESSED_FOLDER"
        echo "  ALBUMS:     $ALBUMS_FOLDER"
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo ""
    } > "$REPORT_FILE"
    
    log_success "Report generated: $REPORT_FILE"
    echo ""
    cat "$REPORT_FILE"
}

################################################################################
# Step 9: Show Post-Migration Instructions
################################################################################
show_post_migration_instructions() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            MIGRATION PREPARATION COMPLETE! 🎉              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Your processed photo library is ready at:${NC}"
    echo ""
    echo "  📁 ALL_PHOTOS: $PROCESSED_FOLDER"
    echo "  � ALBUMS:     $ALBUMS_FOLDER"
    echo ""
    echo -e "${BLUE}Quick Actions:${NC}"
    echo ""
    echo "  Open ALL_PHOTOS folder:"
    echo "    open \"$PROCESSED_FOLDER\""
    echo ""
    echo "  Open ALBUMS folder:"
    echo "    open \"$ALBUMS_FOLDER\""
    echo ""
    echo "  Open Proton Drive:"
    echo "    open -a \"Proton Drive\""
    echo ""
    echo -e "${YELLOW}⚠️  IMPORTANT: Keep your original Takeout files as backup${NC}"
    echo -e "${YELLOW}    until you've verified everything in Proton Drive!${NC}"
    echo ""
    
    # Offer to open folders
    read -p "Would you like to open the output folder now? (y/n): " OPEN_FOLDER
    if [[ "$OPEN_FOLDER" =~ ^[Yy]$ ]]; then
        open "$OUTPUT_FOLDER"
    fi
}

################################################################################
# Main Execution
################################################################################
main() {
    clear
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Google Photos → Proton Drive Migration Script             ║"
    echo "║  macOS Edition                                             ║"
    echo "║                                                            ║"
    echo "║  This script will:                                         ║"
    echo "║  • Merge JSON metadata into photo EXIF                     ║"
    echo "║  • Fix timestamps to reflect actual photo date             ║"
    echo "║  • Remove only Live Photo videos (MOV paired with HEIC)    ║"
    echo "║  • Remove duplicates                                       ║"
    echo "║  • Organize by year and recreate albums                    ║"
    echo "║  • Validate album photos exist in ALL_PHOTOS               ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    # Step 1: Check prerequisites
    log_info "Step 1/7: Checking prerequisites..."
    check_prerequisites
    echo ""
    
    # Step 2: Get paths
    log_info "Step 2/7: Setting up paths..."
    get_user_paths
    echo ""
    
    # Step 3: Setup helper tool
    log_info "Step 3/7: Setting up google-photos-takeout-helper..."
    setup_takeout_helper
    echo ""
    
    # Step 4: Process photos
    log_info "Step 4/7: Processing photos and merging metadata..."
    process_photos_with_metadata
    echo ""
    
    # Step 5: Deduplicate (tool already does this, but we do an extra pass)
    log_info "Step 5/7: Checking for remaining duplicates..."
    deduplicate_photos "$PROCESSED_FOLDER"
    deduplicate_photos "$ALBUMS_FOLDER"
    echo ""
    
    # Step 6: Organize and summarize
    log_info "Step 6/7: Organizing and summarizing..."
    organize_albums
    echo ""
    
    # Step 7: Verify & Report
    log_info "Step 7/7: Verifying and generating report..."
    verify_metadata "$PROCESSED_FOLDER"
    echo ""
    
    generate_report
    echo ""
    
    show_post_migration_instructions
}

# Run main function
main
