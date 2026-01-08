# Google Photos to Proton Drive Migration Script

A macOS bash script that transforms Google Photos Takeout exports into a clean, de-duplicated, and properly organized photo library ready for upload to Proton Drive.

## 🎯 Purpose

This script solves the challenge of migrating your entire Google Photos library to Proton Drive by:

- **Collecting ALL photos** from both date folders AND album folders into one unified library
- **Merging JSON metadata** from Google Takeout into file EXIF data
- **Fixing timestamps** so photos reflect their actual creation date (not export date)
- **Removing Live Photo videos** (the short video clips paired with photos)
- **Filtering short videos** (keeps only videos 5 seconds or longer)
- **De-duplicating** photos across multiple Takeout archives
- **Organizing by year** into a single `ALL_PHOTOS` folder
- **Generating a detailed report** with counts, sizes, and upload instructions

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
Takeout:  /Users/yourname/Downloads/GoogleTakeout/Takeout/Google Photos
Output:   /Users/yourname/ProcessedPhotos
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
├── ALBUMS/                  # Album structure preserved for reference
│   ├── Vacation 2020/
│   │   ├── beach.jpg
│   │   └── sunset.jpg
│   ├── Family/
│   └── ...
├── MIGRATION_REPORT.txt     # Detailed statistics and instructions
└── duplicates.log           # Any duplicate files found (if any)
```

**Key Points:**
- `ALL_PHOTOS` contains every photo/video organized by year - upload this to Proton Drive Photos
- `ALBUMS` contains copies organized by album name - use for reference when creating albums in Proton Drive
- All album photos are validated to exist in `ALL_PHOTOS`, so no re-uploading is needed when creating albums

## 📤 Uploading to Proton Drive

### Using Proton Drive Desktop App or Web

1. Open Proton Drive on your Mac or go to [drive.proton.me](https://drive.proton.me)
2. Navigate to the **Photos** section
3. Drag and drop the contents of `ALL_PHOTOS` folder
4. Proton Drive will automatically organize by EXIF date

### Creating Albums in Proton Drive

Since all album photos are validated to exist in `ALL_PHOTOS`:
1. Upload `ALL_PHOTOS` first (this is your main photo timeline)
2. In Proton Drive Photos, create new albums
3. Select photos from your uploaded library to add to albums
4. Use the `ALBUMS` folder as a reference for which photos belong to each album

**No duplicate uploading required!** Every photo in `ALBUMS` is guaranteed to already exist in `ALL_PHOTOS`.

## 🔧 What Gets Filtered

### Live Photos
The script detects and removes Live Photo video components by looking for video files that have a matching image file with the same base name. For example:
- `IMG_1234.HEIC` (kept - the photo)
- `IMG_1234.MOV` (removed - the Live Photo video)

### Short Videos
Videos under 5 seconds are automatically removed. This filters out:
- Live Photo videos that weren't caught by name matching
- Accidental recordings
- Burst video clips

Videos 5 seconds or longer are kept and have their metadata fixed.

## 🛠️ What Each Step Does

| Step | Action | Time |
|------|--------|------|
| 1 | Checks Homebrew, Python, exiftool, jq | ~5 seconds |
| 2 | Collects input paths from you | Interactive |
| 3 | Sets up tools | ~30 seconds |
| 4 | Processes ALL photos, filters videos, merges metadata | Varies* |
| 5 | Final de-duplication pass | Varies* |
| 6 | Organizes, verifies, generates report | ~1 minute |

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
- **Folder structure** - Organized by year
- **Naming conflicts** - Resolved automatically with timestamp suffixes

## ⚠️ Important Notes

1. **Backup your originals** - Keep the original Takeout export until you verify everything in Proton Drive
2. **Disk space** - You'll need space for both original Takeout + processed output (roughly 2x your photo library size)
3. **macOS only** - This script is designed specifically for macOS
4. **Empty folders** - Removed automatically during organization
5. **Large libraries** - The script provides progress indicators but can take time with 100k+ photos
6. **Album validation** - The script ensures every album photo exists in `ALL_PHOTOS` so you only need to upload once

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

**Important:** Photos can exist in both "Photos from YYYY" folders AND album folders. This script collects from ALL locations and de-duplicates, ensuring no photos are missed.

## 🚀 Next Steps

After migration:

1. ✅ Verify photos in `ALL_PHOTOS` folder look correct
2. ✅ Check `MIGRATION_REPORT.txt` for statistics  
3. ✅ Upload `ALL_PHOTOS` contents to Proton Drive Photos
4. ✅ Verify dates and organization in Proton Drive
5. ✅ Keep original Takeout as backup for a few weeks
6. ✅ Delete original Takeout when confident everything is correct

---

**Happy migrating! 📸 → 🔒**
