"""Balance compiled UI test classes and keep any additional Xcode tests in the final shard."""

import argparse
import re
from collections import defaultdict
from pathlib import Path


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("inventory", type=Path)
parser.add_argument("shard", type=int)
parser.add_argument("count", type=int)
parser.add_argument("--xcodebuild-arguments", action="store_true")
parser.add_argument("--expected", type=Path)
args = parser.parse_args()

target = "MyFitPlateUITests"
method_symbol = re.compile(r"@objc MyFitPlateUITests\.(\w+)\.(test\w+)\(\)(?: .*)?")
cases = defaultdict(set)
for line in args.inventory.read_text().splitlines():
    entry = line.strip()
    if entry.startswith(target + "/"):
        suite, method = entry.rsplit("/", 1)
    else:
        match = method_symbol.fullmatch(entry)
        if not match:
            continue
        suite = f"{target}/{match[1]}"
        method = f"{match[2]}()"
    cases[suite].add(method)

if not 1 <= args.shard <= args.count <= len(cases):
    parser.error(f"Found {len(cases)} UI test classes for {args.count} shards (requested shard {args.shard})")

groups = [[] for _ in range(args.count)]
loads = [0] * args.count
for suite in sorted(cases, key=lambda name: (-len(cases[name]), name)):
    group = min(range(args.count), key=loads.__getitem__)
    groups[group].append(suite)
    loads[group] += len(cases[suite])

selected = groups[args.shard - 1]
if args.expected:
    identifiers = sorted(f"{suite.removeprefix(target + '/')}/{method}" for suite in selected for method in cases[suite])
    args.expected.write_text("\n".join(identifiers) + "\n")

if not args.xcodebuild_arguments:
    print("\n".join(selected))
elif args.shard == args.count:
    # Let XCTest run every remaining test, including cases supplied by a different test framework.
    print(f"-only-testing:{target}")
    for earlier_group in groups[:-1]:
        for suite in earlier_group:
            print(f"-skip-testing:{suite}")
else:
    for suite in selected:
        print(f"-only-testing:{suite}")
