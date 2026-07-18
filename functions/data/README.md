# Canadian Nutrient File 2026

`cnf-2026.json` is a compact, generated subset of Health Canada's Canadian Nutrient File 2026.
It contains the foods and nutrients supported by MyFitPlate, normalized to the app's established
units. Values remain per 100 grams.

Source: Health Canada, Canadian Nutrient File 2026

Dataset: https://open.canada.ca/data/en/dataset/1b6139bd-ed7e-4043-bc28-ff00e10f3109

Licence: Open Government Licence - Canada 2.0

https://open.canada.ca/en/open-government-licence-canada

Rebuild from the official extracted CSV directory:

```sh
python3 tools/build_cnf_2026.py /path/to/cnf-2026-csv functions/data/cnf-2026.json
```
