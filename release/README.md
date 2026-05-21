# release/

Public, git-tracked outputs from the Tariff Rate Tracker. Each publication
overwrites the previous one — only the latest set of files lives on disk at
any time. To browse historical publications, use git:

```bash
git log -- release/
git log -p release/MANIFEST.json   # see what shipped each time
git show <SHA>:release/data/daily_overall_<DATE>.csv   # recover a specific file
```

## When this folder updates

It updates **only when a build runs with `--publish-git`** — not on every
build. Default builds do not touch this folder.

```bash
Rscript src/00_build_timeseries.R --full --core-only --publish-git
```

To produce both an internal NFS vintage and a public release in one go:

```bash
Rscript src/00_build_timeseries.R --full --core-only --publish-internal --publish-git
```

See [docs/build.md](../docs/build.md#publishing) for the difference between
`--publish-internal` and `--publish-git`.

## Files

Filenames carry the publication date as a suffix, so every release is
self-identifying.

| File pattern                              | Format  | Description |
|-------------------------------------------|---------|-------------|
| `data/rate_timeseries_YYYY-MM-DD.parquet` | parquet | Full HTS10×country×date panel of statutory rates. Parquet because the CSV form is large; read with `arrow`, `pandas`, or `duckdb`. |
| `data/daily_overall_YYYY-MM-DD.csv`       | csv     | Daily aggregate effective tariff rate (overall). |
| `data/daily_by_country_YYYY-MM-DD.csv`    | csv     | Daily aggregate effective rate by partner country. |
| `data/daily_by_authority_YYYY-MM-DD.csv`  | csv     | Daily aggregate by tariff authority (S232, IEEPA, etc.). |
| `data/daily_by_category_YYYY-MM-DD.csv`   | csv     | Daily aggregate by product category. |
| `MANIFEST.json`                           | json    | Publication date, data-as-of revision date, source git SHA, per-file size + sha256 + row count. |

Parquet is used only for the rate panel; daily aggregates stay CSV so they
remain grep-friendly and diff-readable.

## Reading in Python

```python
import pandas as pd
panel = pd.read_parquet("release/data/rate_timeseries_2026-05-21.parquet")
daily = pd.read_csv("release/data/daily_overall_2026-05-21.csv")
```

## Citation

See [CITATION.cff](../CITATION.cff) at the repo root and the "Citing this
work" section of the main [README](../README.md).
