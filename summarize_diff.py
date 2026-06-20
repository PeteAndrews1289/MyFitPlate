import re
from collections import defaultdict

with open('codex_diff.txt', 'r') as f:
    lines = f.readlines()

current_file = None
changes = defaultdict(list)

for line in lines:
    if line.startswith('diff --git a/'):
        parts = line.strip().split(' b/')
        if len(parts) == 2:
            current_file = parts[1]
    elif current_file and (line.startswith('+') or line.startswith('-')) and not line.startswith('+++') and not line.startswith('---'):
        changes[current_file].append(line.strip())

for file, file_changes in changes.items():
    if "pbxproj" in file or "plist" in file: continue
    adds = len([c for c in file_changes if c.startswith('+')])
    dels = len([c for c in file_changes if c.startswith('-')])
    print(f"{file}: {adds} additions, {dels} deletions")

