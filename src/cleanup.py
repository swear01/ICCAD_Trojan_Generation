#!/usr/bin/env python3
"""
Simple script to delete files with configurable number ranges from data directories.
Deletes result{x}.txt files from data/label/ and design{x}.v files from data/netlist/.
"""

# ==================== CONFIG VARIABLES ====================
# Modify these variables as needed:

# Number range to delete (inclusive)
START_NUMBER = 30
END_NUMBER = 371

# Set to True to only show what would be deleted (dry run)
# Set to False to actually delete the files
DRY_RUN = False

# Set to True to only delete from label directory
LABEL_ONLY = False

# Set to True to only delete from netlist directory  
NETLIST_ONLY = False

# ========================================================

import os
import glob
from pathlib import Path


def delete_files_in_range(directory, pattern, start_num, end_num, dry_run=True):
    """
    Delete files matching the pattern with numbers in the specified range.
    """
    if not os.path.exists(directory):
        print(f"Warning: Directory {directory} does not exist")
        return []
    
    deleted_files = []
    
    # Get all files matching the pattern
    search_pattern = os.path.join(directory, pattern)
    matching_files = glob.glob(search_pattern)
    
    for file_path in matching_files:
        filename = os.path.basename(file_path)
        
        # Extract number from filename
        if filename.startswith("result") and filename.endswith(".txt"):
            number_str = filename[6:-4]  # Remove "result" prefix and ".txt" suffix
        elif filename.startswith("design") and filename.endswith(".v"):
            number_str = filename[6:-2]  # Remove "design" prefix and ".v" suffix
        else:
            continue
        
        try:
            file_number = int(number_str)
            if start_num <= file_number <= end_num:
                if dry_run:
                    print(f"Would delete: {file_path}")
                else:
                    os.remove(file_path)
                    print(f"Deleted: {file_path}")
                deleted_files.append(file_path)
        except ValueError:
            # Skip files where the number part can't be converted to int
            continue
    
    return deleted_files


def main():
    print("=" * 60)
    print("FILE DELETION SCRIPT")
    print("=" * 60)
    print(f"Number range: {START_NUMBER} to {END_NUMBER}")
    print(f"Dry run: {DRY_RUN}")
    print(f"Label only: {LABEL_ONLY}")
    print(f"Netlist only: {NETLIST_ONLY}")
    print("-" * 60)
    
    if START_NUMBER > END_NUMBER:
        print("Error: START_NUMBER must be less than or equal to END_NUMBER")
        return
    
    # Get the current directory (assuming script is in root)
    current_dir = Path.cwd()
    data_dir = current_dir / "data"
    
    print(f"Current directory: {current_dir}")
    print(f"Data directory: {data_dir}")
    print("-" * 60)
    
    total_deleted = 0
    
    # Delete files from data/label/ directory
    if not NETLIST_ONLY:
        label_dir = data_dir / "label"
        print(f"\nProcessing label directory: {label_dir}")
        deleted_label = delete_files_in_range(
            str(label_dir), 
            "result*.txt", 
            START_NUMBER, 
            END_NUMBER, 
            DRY_RUN
        )
        print(f"Label files to be deleted: {len(deleted_label)}")
        total_deleted += len(deleted_label)
    
    # Delete files from data/netlist/ directory
    if not LABEL_ONLY:
        netlist_dir = data_dir / "netlist"
        print(f"\nProcessing netlist directory: {netlist_dir}")
        deleted_netlist = delete_files_in_range(
            str(netlist_dir), 
            "design*.v", 
            START_NUMBER, 
            END_NUMBER, 
            DRY_RUN
        )
        print(f"Netlist files to be deleted: {len(deleted_netlist)}")
        total_deleted += len(deleted_netlist)
    
    print("-" * 60)
    print(f"Total files to be deleted: {total_deleted}")
    
    if DRY_RUN and total_deleted > 0:
        print("\nTo actually delete these files, set DRY_RUN = False in the config variables")
    elif total_deleted == 0:
        print("\nNo files found in the specified range")
    
    print("=" * 60)


if __name__ == "__main__":
    main()
