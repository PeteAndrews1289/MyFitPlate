#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys


def parse_args():
    parser = argparse.ArgumentParser(description="Check Xcode line coverage from an xcresult bundle.")
    parser.add_argument("result_bundle", help="Path to the .xcresult bundle.")
    parser.add_argument("--minimum", type=float, default=float(os.environ.get("COVERAGE_MINIMUM", "0")))
    parser.add_argument("--target", help="Optional target name to check instead of overall coverage.")
    return parser.parse_args()


def load_report(result_bundle):
    try:
        output = subprocess.check_output(
            ["xcrun", "xccov", "view", "--report", "--json", result_bundle],
            text=True
        )
    except subprocess.CalledProcessError as error:
        print(error.output, file=sys.stderr)
        raise
    return json.loads(output)


def coverage_for_target(report, target_name):
    targets = report.get("targets", [])
    for target in targets:
        if target.get("name") == target_name:
            return target_name, target.get("lineCoverage", 0) * 100

    available = ", ".join(target.get("name", "unknown") for target in targets)
    raise SystemExit(f"Coverage target '{target_name}' not found. Available targets: {available}")


def overall_coverage(report):
    if isinstance(report.get("lineCoverage"), (int, float)):
        return "overall", report["lineCoverage"] * 100

    app_targets = [
        target for target in report.get("targets", [])
        if not target.get("name", "").endswith(".xctest")
    ]
    if app_targets:
        target = app_targets[0]
        return target.get("name", "app"), target.get("lineCoverage", 0) * 100

    raise SystemExit("No coverage information was found in the result bundle.")


def main():
    args = parse_args()
    label, coverage = coverage_for_target(load_report(args.result_bundle), args.target) if args.target else overall_coverage(load_report(args.result_bundle))

    print(f"Line coverage for {label}: {coverage:.2f}%")
    if coverage < args.minimum:
        raise SystemExit(f"Coverage {coverage:.2f}% is below the required {args.minimum:.2f}% floor.")


if __name__ == "__main__":
    main()
