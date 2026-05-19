# Scenarios and Counterfactuals

The tracker can produce counterfactual daily series alongside the baseline.
Each scenario is a named transformation of the rate schema — e.g. "what if
IEEPA reciprocal had never been imposed?" or "what if the EU 232 auto floor
moves from 15% to 25% on 2026-05-04?"

Scenarios live in [`config/scenarios.yaml`](../config/scenarios.yaml). Outputs
land in `output/alternative/`, one CSV per scenario per output type.

## TL;DR

```yaml
# config/scenarios.yaml
baseline:
  description: 'All current tariffs active'
  disable: []

no_ieepa:
  description: 'Remove all IEEPA tariffs (reciprocal + fentanyl)'
  disable: [ieepa_reciprocal, ieepa_fentanyl]

eu_auto_25pct:
  description: 'EU 232+MFN auto floor raised from 15% to 25% on 2026-05-04'
  patches:
    - filter:
        country_group: eu
        product_set: auto_vehicles
        from_date: '2026-05-04'
      action:
        type: floor
        column: rate_232
        value: 0.25
```

Then:

```bash
Rscript src/00_build_timeseries.R --full          # runs all scenarios in scenarios.yaml
```

Each scenario writes `output/alternative/daily_overall_<scenario>.csv` and
companion `by_authority_*.csv`, `by_country_*.csv`, and
`by_category_*.csv`.

## The two scenario formats

A scenario can use either or both of `disable:` and `patches:`. When both are
present, `disable:` runs first (it zeros entire authority columns) and
`patches:` runs second on the modified rates. Stacking rules are re-applied
once at the end.

### `disable:` — zero out entire authorities

```yaml
no_ieepa_recip:
  description: 'Remove IEEPA reciprocal only (keep fentanyl)'
  disable: [ieepa_reciprocal]
```

Accepted authority keys (defined in `policy_params.yaml → AUTHORITY_COLUMNS`):

| Key | Affects column |
|---|---|
| `section_232` | `rate_232` |
| `section_301` | `rate_301` |
| `ieepa_reciprocal` | `rate_ieepa_recip` |
| `ieepa_fentanyl` | `rate_ieepa_fent` |
| `section_122` | `rate_s122` |
| `other` | `rate_other` |

This is the legacy format. Use it when you want a coarse "off switch" for one
or more whole authorities.

### `patches:` — date-bounded targeted overrides

```yaml
eu_auto_25pct:
  patches:
    - filter:
        country_group: eu
        product_set: auto_vehicles
        from_date: '2026-05-04'
      action:
        type: floor
        column: rate_232
        value: 0.25
```

Each patch is a `filter` + `action` pair. A scenario can have multiple patches;
they're applied in order.

#### `filter` keys

| Key | Required | Accepts | Notes |
|---|---|---|---|
| `country_group` | yes | mnemonic (`all`, `eu`, `china`, `canada`, `mexico`, `uk`, `japan`, `floor_countries`) **or** a YAML list of Census codes | `all` resolves to NULL (no country restriction). Unknown mnemonics fall through and are treated as a single Census code. |
| `product_set` | yes | mnemonic (`auto_vehicles`, `auto_parts`, `mhd_vehicles`, `mhd_parts`) **or** a single key from `policy_params.yaml → section_232_headings` | Mnemonics expand to multiple headings; single-key form resolves to one heading's prefixes. Empty resolution is a hard error. |
| `from_date` | no | `YYYY-MM-DD` | Patch only applies to intervals starting on or after this date. Omit for "always on". |

#### `action` keys

| Key | Required | Accepts | Notes |
|---|---|---|---|
| `type` | no (defaults to `floor`) | `floor` | Only `floor` is implemented today. |
| `column` | yes | any `rate_*` column in the schema | E.g. `rate_232`, `rate_ieepa_recip`. Errors if the column is absent. |
| `value` | yes | numeric (decimal, e.g. `0.25` for 25%) | Target all-in rate. |

**`floor` semantics:** sets the target column so the all-in rate (`column + base_rate`) hits `value`, taking `max(value - base_rate, 0)` so we don't subsidize products with `base_rate > value`. This mirrors how the EU/JP/KR auto-deal floors work in `06_calculate_rates.R`.

## How scenarios run

The build runner calls `run_alternative_series()` after the main build. That
function loads `config/scenarios.yaml`, skips `baseline` (no-op identity),
and iterates the rest per-revision against the on-disk snapshots — never
materializing the full combined timeseries. This is what keeps `no_232` /
`no_s122` runs inside memory bounds.

Two slow scenario classes also exist that REBUILD the timeseries from scratch
with policy-parameter overrides (e.g. `metal_flat`, `usmca_2024`). These
only run when invoked explicitly:

```bash
# Run all rebuild alternatives:
Rscript src/00_build_timeseries.R --with-alternatives

# Run a subset:
Rscript src/00_build_timeseries.R --with-alternatives \
    --rebuild-alts metal_flat,usmca_2024

# Iterate existing snapshots without rebuilding the main series:
Rscript src/00_build_timeseries.R --alternatives-only
```

Available rebuild-alt names: `usmca_annual`, `usmca_monthly`, `usmca_2024`,
`usmca_dec2025`, `metal_flat`, `dutyfree_nonzero`, `subdivision_r_mid`.

## Outputs

Per scenario named `<variant>` (everything except `baseline`):

| Path | Description |
|---|---|
| `output/alternative/daily_overall_<variant>.csv` | Daily overall ETR series |
| `output/alternative/by_authority_<variant>.csv` | Authority decomposition (interval-encoded) |
| `output/alternative/by_country_<variant>.csv` | Per-country aggregates (interval-encoded) |
| `output/alternative/by_category_<variant>.csv` | Per-GTAP-sector aggregates (only when weights available) |

All outputs have a `variant` column with the scenario name so you can stack
them in downstream analysis.

## Adding a scenario

1. Add an entry to `config/scenarios.yaml` (pick a unique name).
2. Decide: `disable:`, `patches:`, or both.
3. Re-run the build; the new scenario shows up in `output/alternative/`
   alongside the existing ones.

For `patches:`, if your filter resolves to an empty product set or unknown
column, the build errors loudly — no silent zero-row outputs.

## Extending the DSL

The patch system is intentionally narrow. To add new capabilities:

- **New `country_group` mnemonics**: extend `resolve_country_group()` in
  `src/apply_scenarios.R`. Mnemonics typically reference fields in
  `policy_params.yaml`.
- **New `product_set` composites**: add an entry to `PATCH_PRODUCT_SETS` in
  `src/apply_scenarios.R`. Values must be valid keys in
  `policy_params.yaml → section_232_headings`.
- **New `action` types** (currently only `floor`): extend `apply_patch()` with
  a new branch. Candidates worth considering: `set` (unconditional override),
  `add` (additive surcharge), `cap` (max rate).

Keep the DSL small. The legacy `disable:` format already handles the
"all-or-nothing per authority" case; `patches:` is for cases that need
finer-grained selection.
