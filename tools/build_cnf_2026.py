#!/usr/bin/env python3
"""Build MyFitPlate's compact Health Canada CNF 2026 search dataset."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


DATASET_RELEASE = "2026-05-14"

# CNF nutrient codes mapped to MyFitPlate's canonical storage keys. CNF values
# are per 100 g. All units already match FoodItem except copper, whose existing
# app unit is micrograms while CNF reports milligrams.
NUTRIENTS: dict[int, tuple[str, float]] = {
    203: ("protein", 1),
    204: ("fat", 1),
    205: ("carbs", 1),
    208: ("calories", 1),
    291: ("fiber", 1),
    301: ("calcium", 1),
    303: ("iron", 1),
    304: ("magnesium", 1),
    305: ("phosphorus", 1),
    306: ("potassium", 1),
    307: ("sodium", 1),
    309: ("zinc", 1),
    312: ("copper", 1_000),
    315: ("manganese", 1),
    317: ("selenium", 1),
    320: ("vitaminA", 1),
    323: ("vitaminE", 1),
    328: ("vitaminD", 1),
    401: ("vitaminC", 1),
    404: ("vitaminB1", 1),
    405: ("vitaminB2", 1),
    406: ("vitaminB3", 1),
    410: ("vitaminB5", 1),
    415: ("vitaminB6", 1),
    417: ("folate", 1),
    418: ("vitaminB12", 1),
    430: ("vitaminK", 1),
    606: ("saturatedFat", 1),
    645: ("monounsaturatedFat", 1),
    646: ("polyunsaturatedFat", 1),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_directory", type=Path)
    parser.add_argument("output_file", type=Path)
    return parser.parse_args()


def csv_rows(path: Path):
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        yield from csv.DictReader(handle)


def finite_nonnegative(value: str) -> float | None:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(parsed) or parsed < 0:
        return None
    return parsed


def compact_number(value: float) -> int | float:
    rounded = round(value, 6)
    if rounded.is_integer():
        return int(rounded)
    return rounded


def later_date(first: str, second: str) -> str:
    return max(first or "", second or "")


def build_dataset(input_directory: Path) -> dict[str, object]:
    foods: dict[int, dict[str, object]] = {}
    for row in csv_rows(input_directory / "Food_Name.csv"):
        food_code = int(row["Food_Code"])
        foods[food_code] = {
            "i": food_code,
            "n": row["Food_Description_EN"].strip(),
            "a": row["Alternate_Description_EN"].strip(),
            "f": int(row["Food_Source_Code"] or 0),
            "d": row["Food_Last_Updated_Date"].strip(),
            "v": {},
            "q": set(),
        }

    for row in csv_rows(input_directory / "Nutrient_Amount.csv"):
        nutrient_code = int(row["Nutrient_Code"])
        mapping = NUTRIENTS.get(nutrient_code)
        if mapping is None:
            continue
        food = foods.get(int(row["Food_Code"]))
        value = finite_nonnegative(row["Nutrient_Amount"])
        if food is None or value is None:
            continue

        key, multiplier = mapping
        values = food["v"]
        assert isinstance(values, dict)
        values[key] = compact_number(value * multiplier)

        sources = food["q"]
        assert isinstance(sources, set)
        if row["Nutrient_Source_Code"]:
            sources.add(int(row["Nutrient_Source_Code"]))
        food["d"] = later_date(
            str(food["d"]),
            row["Nutrient_Last_Updated_Date"].strip(),
        )

    compact_foods: list[dict[str, object]] = []
    for food_code in sorted(foods):
        food = foods[food_code]
        values = food["v"]
        assert isinstance(values, dict)
        if not values or "calories" not in values:
            continue
        sources = food.pop("q")
        assert isinstance(sources, set)
        if sources:
            food["q"] = sorted(sources)
        if not food["a"]:
            food.pop("a")
        compact_foods.append(food)

    return {
        "schema": 1,
        "release": DATASET_RELEASE,
        "source": "Health Canada Canadian Nutrient File 2026",
        "foods": compact_foods,
    }


def main() -> None:
    args = parse_args()
    dataset = build_dataset(args.input_directory)
    args.output_file.parent.mkdir(parents=True, exist_ok=True)
    with args.output_file.open("w", encoding="utf-8") as handle:
        json.dump(dataset, handle, ensure_ascii=True, separators=(",", ":"))
        handle.write("\n")
    print(f"Wrote {len(dataset['foods'])} foods to {args.output_file}")


if __name__ == "__main__":
    main()
