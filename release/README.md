# Tariff Rate Tracker — published data

Daily series of **statutory U.S. import tariff rates**, produced by
[The Budget Lab at Yale](https://budgetlab.yale.edu/). The underlying model
computes the statutory rate for every HTS-10 product × partner country pair
under each revision of the Harmonized Tariff Schedule (and the executive
actions layered on top of it), then aggregates to the daily series published
here.

**Statutory, not collected:** these are the rates the tariff schedule and
executive actions prescribe on entry, not the duties importers actually paid
(which differ through exclusions, drawback, de minimis, timing, and
compliance). Rates are decimals: `0.25` means 25%.

## Files

Filenames carry the publication date, so every release is self-identifying.
Only the **latest** publication lives on disk; prior publications are in git
history:

```bash
git log -- release/                                   # publication history
git show <SHA>:release/data/daily_overall_<DATE>.csv  # recover an old file
```

| File | Description |
|---|---|
| `data/daily_overall_<DATE>.csv` | One row per day: economy-wide average rates. |
| `data/daily_by_country_<DATE>.csv` | One row per day × partner country. |
| `data/daily_by_authority_<DATE>.csv` | One row per day: rates split by legal authority (Section 232, Section 301, IEEPA, Section 122, Section 201, MFN base, other). |
| `data/daily_by_category_<DATE>.csv` | One row per day × GTAP product category. |
| `MANIFEST.json` | Provenance: publication date, the HTS revision the data is current through (`data_as_of`), source git commit, and per-file row counts, sizes, and sha256 checksums. |

## Column guide

Common columns across files:

- `date` — calendar day. The series begins 2025-01-01. Days after the most
  recent HTS revision **assume current policy continues unchanged** out to the
  series horizon — treat trailing dates as a projection of the status quo, not
  a forecast.
- `revision` — the HTS revision in force on that day (e.g. `2026_rev_10`).
  Revisions are dated by **policy effective date** (when a measure legally
  took effect), which can precede the date the revision text was published.
- `mean_additional_*` vs `mean_total_*` — *additional* covers the tariff
  actions layered on since January 2025 (Section 232/301, IEEPA, etc.);
  *total* adds the MFN base rate.
- `*_exposed` vs `*_all_pairs` — *exposed* averages over the product×country
  pairs actually carrying additional-tariff exposure; *all_pairs* spreads the
  same total over the full product×country universe (pairs with no additional
  tariff count as zero).
- `weighted_etr` — import-weighted effective tariff rate (weights from U.S.
  Census import values; `matched_imports_b` / `total_imports_b` in the overall
  file report how many billions of dollars of trade the weights cover).
- `country` — U.S. Census numeric partner code (e.g. `5700` = China), with
  `country_name` alongside.
- In the by-authority file, `mean_<authority>` columns are unweighted means
  and `etr_<authority>` columns are import-weighted; `etr_base` is the MFN
  base.

## Quick start

```python
import pandas as pd
overall = pd.read_csv("release/data/daily_overall_2026-06-09.csv",
                      parse_dates=["date"])
overall.plot(x="date", y="weighted_etr")
```

```r
library(readr)
overall <- read_csv("release/data/daily_overall_2026-06-09.csv")
plot(overall$date, overall$weighted_etr, type = "l")
```

(Adjust the date suffix to the current publication — see `MANIFEST.json` or
just list `data/`.)

## Methodology and caveats

Full documentation lives in the repo: [methodology](../docs/methodology.md),
[assumptions](../docs/assumptions.md), and
[data sources](../DATA_SOURCES.md). Caveats most likely to matter:

- **Specific and compound duties** (e.g. `$1.035/kg + 14.9%`) are not yet
  converted to ad-valorem equivalents and currently contribute 0 — this
  understates rates in chapters where such duties are common (notably
  food products, HS 04/17/19/21).
- Some conditional carve-outs (product-specific exclusions, quantity-limited
  exemptions, content-share conditions) are approximated or unmodeled; see
  [assumptions](../docs/assumptions.md).
- USMCA-eligible Canada/Mexico trade is modeled with claim shares, not
  perfect take-up.

## License and citation

Code and published data are MIT-licensed (see [LICENSE](../LICENSE)). To cite,
use [CITATION.cff](../CITATION.cff) at the repo root — GitHub's "Cite this
repository" button renders it directly. When referencing a specific
publication, include the publication date from `MANIFEST.json` and, ideally,
the `data_as_of` revision it reports.
