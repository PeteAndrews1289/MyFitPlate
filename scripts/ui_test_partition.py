"""Partition the UI suites discovered by Xcode, keeping each XCTestCase on one simulator."""

import sys
from collections import Counter
from pathlib import Path


inventory = Path(sys.argv[1]).read_text().splitlines()
shard, count = map(int, sys.argv[2:])
suites = Counter()
for line in inventory:
    identifier = line.strip()
    if identifier.startswith("MyFitPlateUITests/"):
        suite, _ = identifier.rsplit("/", 1)
        suites[suite] += 1

if not 1 <= shard <= count <= len(suites):
    sys.exit("Expected enough enumerated UI test suites for every shard")

groups = [[] for _ in range(count)]
loads = [0] * count
for suite, tests in sorted(suites.items(), key=lambda item: (-item[1], item[0])):
    group = min(range(count), key=loads.__getitem__)
    groups[group].append(suite)
    loads[group] += tests

print("\n".join(groups[shard - 1]))
