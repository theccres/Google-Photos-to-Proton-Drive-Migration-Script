# Google Photos to Proton Drive Migration Script

A macOS bash script that transforms Google Photos Takeout exports into a clean, de-duplicated, and properly organized photo library ready for upload to Proton Drive.

## 🎯 Purpose

This script solves the challenge of migrating your entire Google Photos library to Proton Drive by:

- **Merging JSON metadata** from Google Takeout into file EXIF data
- **Fixing timestamps** so photos reflect their actual creation date (not export date)
- **De-duplicating** photos across multiple Takeout archives
- **Organizing intelligently** into `ALL_PHOTOS` (by year) and `ALBUMS` (by album name)
- **Preserving GPS coordinates** and other metadata when available
- **Generating a detailed report** with counts, sizes, and upload instructions

## ✨ Features

- ✅ Automatic prerequisite checking and installation
- ✅ Handles multiple Google Takeout exports in a single run
- ✅ Supports all common image formats (JPG, JPEG, PNG, HEIC, GIF, WebP, BMP, TIFF)
- ✅ Supports video formats (MP4, MOV, AVI, MKV, M4V, 3GP)
- ✅ Fixes EXIF DateTimeOriginal and file modification dates
- ✅ Preserves GPS coordinates when available
- ✅ Smart duplicate detection using file hashing
- ✅ Progress indicators for large libraries
- ✅ Comprehensive migration report with statistics
- ✅ Fallback date recovery from folder structure
- ✅ Non-destructive (always works on copies, not originals)

## 📋 Prerequisites

### Required
- **macOS** (10.12+) - This script is macOS-only
- **Homebrew** - Install from [brew.sh](https://brew.sh)
- **Google Takeout export** - Download your photos from [Google Takeout](https://takeout.google.com)

### Automatically Installed
The script will automatically install these via Homebrew if not present:
- Python 3
- `exiftool` (for EXIF metadata handling)
- `jq` (for JSON parsing)
- `google-photos-takeout-helper` (Python package)

## 🚀 Quick Start

### 1. Prepare Your Google Takeout Export

1. Go to [Google Takeout](https://takeout.google.com)
2. Select "Google Photos" only
3. Choose file size and delivery method
4. Download all zip files and extract them into a single folder
5. Optionally merge multiple Takeout exports into one folder

### 2. Run the Script

```bash
# Make the script executable
chmod +x google_photos_migration.sh

# Run it
./google_photos_migration.sh
```

### 3. Follow the Interactive Prompts

The script will ask for:
1. **Path to Takeout folder** - Where you extracted your Google Photos export
2. **Output folder** - Where processed photos should be saved

Example paths:
```
Takeout:  /Users/chase/Downloads/GoogleTakeout/Takeout/Google Photos
Output:   /Users/chase/ProcessedPhotos
```

## 📂 Output Structure

After running, you'll have this structure in your output folder:

```
output_folder/
├── ALL_PHOTOS/              # All photos organized by year
│   ├── 2015/                # Photos from 2015
│   │   ├── photo1.jpg
│   │   └── photo2.jpg
│   ├── 2016/
│   ├── 2017/
│   └── ...
├── ALBUMS/                  # Original album structure preserved
│   ├── Vacation 2020/
│   │   ├── beach1.jpg
│   │   └── sunset.jpg
│   ├── Family/
│   └── ...
├── MIGRATION_REPORT.txt     # Detailed statistics and instructions
└── duplicates.log           # Any duplicate files found (if any)
```

## 📤 Uploading to Proton Drive

### Method 1: Using Proton Drive Desktop App

1. Open Proton Drive on your Mac
2. Navigate to the **Photos** section
3. Drag and drop the contents of `ALL_PHOTOS` folder
4. Proton Drive will automatically organize by EXIF date

### Method 2: Using Web Interface

1. Go to [drive.proton.me](https://drive.proton.me)
2. Access the Photos section
3. Upload folders using the web upload feature

### Creating Albums

1. **Upload `ALL_PHOTOS` first** - This becomes your main photo timeline
2. In Proton Drive Photos, create new albums matching your original album names
3. Either:
   - Re-upload the `ALBUMS` folder contents to each album, OR
   - Select already-uploaded photos and add them to albums

> **Tip:** Proton Drive will use the corrected EXIF DateTimeOriginal to automatically sort everything chronologically.

## 🔧 Usage Examples

### Basic usage (interactive):
```bash
./google_photos_migration.sh
```

### Processing specific Takeout export:
```bash
./google_photos_migration.sh
# When prompted, enter:
# Takeout path: ~/Downloads/takeout-20250107
# Output path: ~/ProcessedPhotos
```

### Handling multiple exports:
1. Merge all Takeout exports into a single folder:
   ```bash
   mkdir ~/MergedTakeout
   cp -r ~/takeout1/Takeout ~/MergedTakeout/
   cp -r ~/takeout2/Takeout ~/MergedTakeout/
   ```
2. Run the script with the merged folder path

## 🛠️ What Each Step Does

| Step | Action | Time |
|------|--------|------|
| 1 | Checks Homebrew, Python, exiftool, jq | ~5 seconds |
| 2 | Collects input paths from you | Interactive |
| 3 | Installs google-photos-takeout-helper | ~30 seconds |
| 4 | Processes photos, merges JSON metadata | Varies* |
| 5 | De-duplicates across collections | Varies* |
| 6 | Organizes final structure | ~1 minute |
| 7 | Generates report and shows results | ~1 minute |

*Time depends on library size. For reference:
- 10,000 photos: ~5-10 minutes
- 50,000 photos: ~20-30 minutes
- 100,000+ photos: ~1+ hour

## 📊 What Gets Fixed

### Timestamps
- **EXIF DateTimeOriginal** - Set from Google's original timestamp
- **EXIF CreateDate** - Synchronized with DateTimeOriginal
- **File modification time** - Updated to match photo date (not export date)

### Metadata
- **GPS coordinates** - Preserved when available
- **Image descriptions** - Maintained from metadata
- **Video dates** - Fixed for all video formats

### Organization
- **Duplicates** - Removed using MD5 hash comparison
- **Folder structure** - Organized by year and album name
- **Naming conflicts** - Resolved automatically

## ⚠️ Important Notes

1. **Backup your originals** - Keep the original Takeout export until you verify everything in Proton Drive
2. **Disk space** - You'll need space for both original Takeout + processed output (roughly 2x your photo library size)
3. **macOS only** - This script is designed specifically for macOS. Linux/Windows users should adapt as needed
4. **Empty folders** - Removed automatically during organization
5. **Large libraries** - The script provides progress indicators but can take time with 100k+ photos
6. **JSON matching** - The script tries multiple strategies to match JSON sidecars to photos

## 🐛 Troubleshooting

### "Homebrew not found"
Install Homebrew from [brew.sh](https://brew.sh):
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### "Takeout folder not found"
Verify the path exists and contains a `Google Photos` subfolder:
```bash
ls -la ~/path/to/your/takeout/
```

### Script stops unexpectedly
Check error messages in terminal. Common causes:
- Insufficient disk space
- Permission issues with output folder
- Invalid Takeout structure

Fix permissions:
```bash
chmod -R 755 ~/path/to/output/folder
```

### Dates still showing as 2026 (current year)
This happens when JSON metadata isn't found. The script falls back to using the folder year.
- Verify Takeout structure: `find ~/takeout -name "*.json" | head -5`
- Some photos may genuinely not have metadata

### Too many duplicates being removed
The script uses MD5 hash comparison. To check what's being removed:
```bash
cat ~/output/path/duplicates.log
```

## 🔐 Privacy & Security

- This script runs **entirely on your local Mac**
- No data is sent to any external service
- All processing is done with standard Unix tools
- Original files are never modified
- Output can be reviewed before uploading to Proton Drive

## 📝 License

This script is provided as-is for personal use. Modify and distribute as needed.

## 💬 Support

If you encounter issues:

1. Check the `MIGRATION_REPORT.txt` in your output folder
2. Review the troubleshooting section above
3. Verify your Takeout structure matches expected format
4. Ensure all prerequisites are installed

## 🎓 Understanding Your Google Takeout

Google Takeout structure typically looks like:
```
Takeout/
└── Google Photos/
    ├── Photos from 2015/
    │   ├── photo1.jpg
    │   ├── photo1.jpg.json
    │   └── ...
    ├── Photos from 2016/
    ├── [Album name]/
    │   ├── photo2.jpg
    │   ├── photo2.jpg.json
    │   └── ...
    └── ...
```

The `.json` files contain the metadata (timestamps, GPS, etc.) that this script extracts and applies to the photos.

## 🚀 Next Steps

After migration:

1. ✅ Verify photos in processed folders
2. ✅ Check `MIGRATION_REPORT.txt` for statistics  
3. ✅ Upload `ALL_PHOTOS` to Proton Drive
4. ✅ Create albums in Proton Drive and populate with `ALBUMS` content
5. ✅ Verify dates and organization in Proton Drive
6. ✅ Keep original Takeout as backup for a few weeks
7. ✅ Delete original Takeout when confident everything is correct

---

**Happy migrating! 📸 → 🔒**
