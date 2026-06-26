# Tariff Rate Tracker — TODO archive

Resolved/closed sections moved out of [todo.md](todo.md) to keep the active list small.
Nothing here is open work — it is kept for historical/reference context only.

## Extreme-eta review fixes (2026-06-04)

Source: `docs/tracker_review_extreme_etas.md` (eval-side Census-vs-statutory etas) + code/snapshot verification against the 2026-05-08 rebuild (all findings confirmed live, not stale). Ordered by dependency and money, not by the review doc's original ranking. Verification details in `tariff_tracker_investigated_issues.md` (memory) — two of the doc's proposed mechanisms were wrong; the items below reflect the corrected root causes.

- [x] **1. Keep 8-digit leaf HTS lines (universe gap, 473 lines).** DONE 2026-06-04 (commit "Keep 8-digit leaf HTS lines..."). `parse_products()` keeps 8-digit leaves, pads to 10 with "00", drops non-leaf 8-digit rows in a post-pass. +473 hts10 (378 ch98, 95 ch91); Swiss watches now carry the 15% framework surcharge; zero rate changes on the pre-existing universe. New validation harness: `scripts/rebuild_one_revision.R` (single-revision scratch rebuild).
- [x] **2. Un-sweep general-purpose computers from 232 auto parts ($17.6B Taiwan ch84 gap).** DONE 2026-06-04. Note 33(g) legally lists bare `8471`, but its operative scope is "parts of passenger vehicles ... and light trucks" — a laptop is not one. New `applicability_shares_file` on the auto_parts heading config (`resources/s232_auto_parts_applicability.csv`, longest-prefix match; share 0 = excluded, fractional = rate blending); interim calibration 8471 = 0. Taiwan 8471 rate_232 → 0 except the 8471.80.4000 semi GPU line. Companion resolved: 8473 lines are CORRECT as-is — Annex II names only 8473.30 and all its children are already exempt; the 20% on 8473.21/.29/.40/.50 is statutory.
- [x] **3. India Annex II inheritance + ch98 across all EOs (~$2.3B).** DONE 2026-06-04. Legal text verified: note 2(z)(ii) routes India 9903.01.84 through heading 9903.01.86 to the FULL note 2(v)(iii) list (so Annex II DOES apply to India, unlike Brazil whose 9903.01.77 has its own enumerated list); every country-EO note carries the standard ch98 claim paragraph. New `country_eo_annex_ii_inherit: ['9903.01.84']` config + ch98 channel in both IEEPA blocks of `06_calculate_rates.R`. India 3004 → 0 on all 124 lines; Brazil 3004 stays 40% (correct); India/Brazil 9801 → 0.
- [x] **4. Re-run `expand_ieepa_exempt.R` (ch97 Berman).** DONE 2026-06-04. Re-ran against a refreshed universe (`scripts/refresh_product_caches.R`): +424 codes (378 new ch98 leaves, 30 ch97, 16 ch49). Audit removals preserved (0 PV codes, 0 non-8523.51). Write-back now preserves the date-window columns.
- [x] **5. Effective-date the IEEPA exempt list.** DONE 2026-06-04 — and bigger than scoped. `scripts/build_annex_ii_dates.R` extracts the note 2(v)(iii)(a) enumeration from every chapter-99 PDF, dates each entry by first appearance using the LEGAL amendment dates from the change records (electronics 2025-04-05 retroactive; EO 14346 metals/gold 2025-09-08; ag expansion 2025-11-13), and END-dates removals (copper → 232 PP 10962, exempt through 2025-07-31; wood → 232 PP 10976, through 2025-10-13; +405 windowed entries appended that were missing entirely). Loader filters in `06_calculate_rates.R` + `generate_etrs_config.R`. Also removed 74 ch06 entries — see discoveries below.
- [x] **6. USMCA eligibility false negatives.** DONE 2026-06-04. Two real root causes: (a) `extract_usmca_eligibility()` read each 10-digit item's own `special` field, but special lives on 8-digit LEGAL lines — statistical suffixes (~59% of HTS10s) were false-negative; now inherits via a legal-line stack (mirrors base-rate inheritance) and handles 8-digit leaves. (b) The h2_average share loader mapped zero-trade pairs to share 0 and absent pairs defaulted to 0 at the join; now zero-trade → NA and application falls back HTS10 → HS8 value-weighted share → 0 (fixes 2709.00.20.10 full-10% vs sibling ≈0). Residual: 7108.12.10.17 ($576M, observed claim share 0.001 with positive trade) — likely monetary gold; needs a bullion-channel decision (below).
- [x] **Companion (diagnostics): universe completeness check. DONE 2026-06-10.** `report_universe_completeness()` in `src/diagnostics.R` (wired into `run_all_diagnostics()`): per-revision comparison of the Census import-weights HS10 universe vs the snapshot universe, classifying each Census code as exact / hs8_drift (suffix concordance) / missing_line (true gap), with import-value shares; flags revisions with >0.1% of import value on missing lines; writes `output/diagnostics/universe_completeness.csv` + `universe_missing_detail.csv`. Skips gracefully when no weights file is present (unweighted/CI environments). Needs a weighted environment (cluster) to produce output — run with the next cluster build.

### Discoveries from the 2026-06-04 fix pass

- **revision_dates.csv is mis-dated for rev_25–31** — promoted to active priority 2 above.
- **ch06 flowers were never on the universal Annex II.** 0603/0601/0602/0604 appear ONLY on the Switzerland/Liechtenstein framework annex (2026 notes; `floor_exempt_2026_*.csv` country_group='swiss', 1,681 HTS8). The 74 universal-list ch06 entries (ETRs-alignment inheritance) wrongly exempted flowers for ALL countries — that, not ag-carve-out retroactivity, is the review's negative-eta ch06 cluster. Removed (Swiss imports stay exempt via the floor path). 4 ch06 entries with unknown provenance left in place.
- **No Swiss product exemptions exist in the 2025 HTS text.** rev_29–32 have no Swiss annex (first appears 2026_basic, where floor files already capture it). The rev_29–32 floor files are correct as-is; Nov-Dec 2025 Swiss floor applies without product exemptions per the HTS text of those revisions. If the framework annex was legally effective ~Nov 14 via CSMS ahead of HTS publication, modeling that would need the revision re-dating pass first.
- **Floor scraper hardening:** anchor regex now accepts "As provided FOR in heading(s)" (Nov 2025 restructured wording) and `parse_floor_exempt_products()` takes a per-vintage `targets` param (`scripts/regen_floor_exempt_2025.R` shows usage; ultimately not needed for rev_29–32 but keeps the scraper usable on post-restructure vintages).
- **Note 2(v)(iii)(b) "particular articles" list (9903.02.78: Etrogs, religious items)** is universal but not extracted/dated by `build_annex_ii_dates.R`; its entries are on the exempt list via ETRs alignment with NA dates (always active). Tiny trade; acceptable approximation, noted for completeness.
- **Other no-provenance entries left alone:** ~290 ch29, ~190 ch84/85 etc. exempt entries match no (iii)(a) text but reflect deliberate TPC/CSMS-aligned breadth (generic pharma, electronics clarifications). Do not blanket-remove.
- **Gold 7108 residual (deferred):** with USMCA fixes, the remaining Canada-gold gap concentrates in 7108.12.10.17 — high trade, near-zero observed USMCA claims, near-zero collected duties. Likely monetary/bullion channel (CBP treats bullion as non-dutiable under the Sept 2025 clarification, or the trade is monetary gold outside duty scope). Needs a legal-basis decision before hardcoding an exemption.

## USMCA scenario and share-loading (2026-04-20, last audited 2026-05-19)

Investigation of `usmca_2024` / `usmca_monthly` alternatives and their behavior in the post-SCOTUS / post-annex regime. Originally three open items; two have since resolved silently (see "Completed" below). Only the snapshot rebuild remains.

### Findings

- **`usmca_monthly` was frozen at Dec 2025 for every 2026 revision.** `SCENARIO_SPECS` in `src/build_usmca_scenarios.R` hardcoded `year = 2025L`, and the monthly branch of `load_usmca_product_shares()` clamped `month_num = 12` whenever `effective_date > 2025-12-31`. `resources/usmca_product_shares_2026_01.csv` existed but was never loaded. In `output/alternative/daily_overall_usmca_monthly.csv` the post-Jan-2026 line tracked `usmca_h2avg` within 0.01pp as a direct consequence.
- **`usmca_2024` alternative is firing correctly.** Direct snapshot comparison at `2026_rev_5` (2026-04-06): CA `total_rate` 13.27% (main) vs 14.44% (2024), MX 13.82% vs 14.30%. s122 is the dominant channel (CA 4.80% vs 6.37%; MX 5.55% vs 6.42%). The small ~0.5pp overall-ETR gap in figure 5 is the correct weighted combination given CA/MX import shares and the fact that fentanyl (the big USMCA lever historically) is zeroed post-2026-02-24.
- **Section 122 does receive USMCA reductions for CA/MX** (contra an earlier claim I made). s122 is a universal blanket applied to every non-exempt product-country pair; step 7 of `06_calculate_rates.R` does `rate_s122 = rate_s122 * (1 - usmca_share)`. Verified at `2026_rev_4`: CA mean s122 8.54% (statutory) → 4.80% (effective); MX 8.54% → 5.55%. With IEEPA reciprocal + fentanyl zeroed post-SCOTUS, s122 is now the single biggest place USMCA bites.
- **Annex override does not refresh `s232_usmca_eligible`.** Step 4 sets `s232_usmca_eligible` from pre-annex heading configs (`usmca_exempt:` flag). Step 5c's annex rate override reclassifies products into annex_1a/_1b/_2/_3 but does not touch `s232_usmca_eligible`. A product newly swept into annex_1b that was not in any pre-annex heading list keeps `s232_usmca_eligible = FALSE`, so step 7 will not reduce its rate_232 for CA/MX even if the product is S/S+ in the HTS special field. Potential gap vs ETRs in the post-April regime.

### Completed

- [x] Rewrote monthly branch of `load_usmca_product_shares()` (`src/data_loaders.R:240-267`) to derive target year/month from `effective_date` and walk backward one calendar month at a time until a file is found. Caps at 120 steps; falls through to annual if nothing matches. Verified across 11 test dates from 2024 through 2026-10.
- [x] Removed hardcoded `year = 2025L` from `usmca_monthly` scenario spec (`src/build_usmca_scenarios.R:42`) and from the legacy `--with-alternatives` block in `src/09_daily_series.R:1005-1013`.
- [x] Patched `src/download_usmca_dataweb.R` so current-year queries use a Year-to-Date date range (`timeframeSelectType = 'specificDateRange'`, Jan-through-current-month) instead of `fullYears`, matching DataWeb support guidance for incomplete years.
- [x] **Annex-era `s232_usmca_eligible` refresh — landed in commit `35542ea` (2026-04-28).** `06_calculate_rates.R:2574-2583` re-derives the flag after the annex restructuring override: any annex_1a/1b/3 product that is USMCA-eligible (S/S+ in HTS) and NOT in steel/aluminum chapters (72/73/76) gets `s232_usmca_eligible = TRUE`. Existing passing test in `tests/test_rate_calculation.R` ("Annex-era s232_usmca_eligible refresh: CA/MX rate_232 reduced vs non-USMCA partner"). Re-audited 2026-05-19 against snapshot_2026_rev_5.rds: bulk of annex-era CA/MX S/S+ products correctly get rate_232 reduced; the residual cases that aren't reduced trace to legitimately zero `h2_average` USMCA share (months 7-12 2025 value-weighted), not a refresh bug.
- [x] **2026 monthly USMCA files refreshed (2026-05-03).** `resources/usmca_product_shares_2026_01.csv` and `_02.csv` now present (587KB / 590KB). DataWeb 503 resolved at some point between 2026-04-23 and 2026-05-03; downloader fix from `src/download_usmca_dataweb.R` worked once DataWeb returned. Per Hugh@DataWeb the latest available data is February 2026, so monthly walk-back from later dates correctly freezes at the 2026-02 file.
- [x] **Rebuilt `usmca_monthly` snapshots (2026-05-19, 95.3 min).** Ran `Rscript src/build_usmca_scenarios.R --scenarios usmca_monthly` — 41 per-revision snapshots written to `data/timeseries/usmca_monthly/`, plus 4 output CSVs in `output/alternative/` (daily_overall, by_authority, by_country, by_category). Output verified against expected behavior: 2025-04-15 delta vs baseline = +2.15pp (Q1 2025 utilization ~40-45% vs baseline H2 ~85%), step-up by 2025-07-15 to +0.17pp delta, flat to baseline through 2025-12, then small +0.04pp delta in 2026 reflecting the 2026_01/02 monthly files. Falls back to 2026-02 for dates after Feb 2026 as expected.

### Open work

- *(none — section closed 2026-05-19)*

## Resolved

<details>
<summary>BEA metal derivatives review (2026-04-06)</summary>

Five issues confirmed via code review:
- [x] BEA copper scaling zeros out valid heading rates
- [x] Authority decomposition misses `deriv_type` for steel derivatives
- [x] Exported ETR configs miss `steel_derivatives` metal metadata
- [x] Flat/CBO pipeline for 232 heading/derivative overlaps
- [ ] Steel-derivative US-melted exemption (`9903.81.92`) — DEFERRED (requires product-condition exemption support)

</details>

<details>
<summary>NA propagation bugs (2026-04-08)</summary>

- [x] Daily output NA for basic–rev_3
- [x] Flat metal-content alternative zeroed derivative 232 rates

</details>

<details>
<summary>Earlier resolved items (2026-03 / 2026-04)</summary>

- [x] Pipeline rebuild with copper + MHD fixes (2026-03-25)
- [x] 301 List 4B suspension fix (2026-03-25)
- [x] Full repo review: USMCA, derivatives, policy dates, stacking (2026-04-02)
- [x] Public release code review (2026-04-02)
- [x] Policy-date propagation fixtures (2026-04-08)
- [x] OOM fix: per-revision streaming for rebuild alternatives (2026-04-13)

</details>

---

## Section 232 annex restructuring — Ruled out / Completed

### Ruled out (investigated 2026-04-22)

- [x] **Annex_2 × rate_232 = 0.25 is not a leak**: 480 rows at 25% in rev_5 snapshot, all semi products. Intentional per semi post-stacking override at `src/06_calculate_rates.R:2275-2298` (Note 39(a) — semi articles aren't re-scoped by the April 2026 annex restructuring). Zero non-semi annex_2 rows carry non-zero rates.
- [x] **IEEPA zeroing in rev_4+ is not a regression**: `rate_ieepa_recip = rate_ieepa_fent = 0` for all rev_4/rev_5 rows is the intended effect of `ieepa_invalidation_date: '2026-02-24'` (SCOTUS *Learning Resources v. Trump*). Section 122 replaces the blanket within the 150-day window.

### Completed

- [x] Config, resource CSV, helper, rate logic, 5 unit tests — scaffolding (2026-04-06)
- [x] Prefix-matching order: longest-first (2026-04-09)
- [x] `2026_rev_5` added (effective 2026-04-06) (2026-04-13)
- [x] Full-value stacking fix: `nonmetal_share=0` for annex products (2026-04-13)
- [x] Double-`resources/` path fix + fail-closed guard + quality invariant (2026-04-13)
- [x] Primary chapter coverage: removed `rate_232 > 0` guard, derivative fallback to annex_1b (2026-04-14)
- [x] ETR export: annex-aware program classification in `generate_etrs_config.R` (2026-04-14)
- [x] Integration tests: config-driven path, fail-closed, primary chapter, export parity, quality invariant — 79 tests total (2026-04-14)


## Section 232 semiconductor — Landed / §122 stacking / effective-date note

### Landed (2026-04-21)

- [x] `resources/s232_semi_products.csv` (10 HTS10s under 8471.50 / 8471.80 / 8473.30) + `scripts/build_semi_products.R`
- [x] `resources/semi_qualifying_shares.csv` scaffold (all 1.0, uncalibrated upper bound)
- [x] `config/policy_params.yaml` `section_232_headings.semiconductors` entry (no USMCA carve-out per Note 39(a); `end_use_exemption_share` parameter)
- [x] `classify_authority()` routes `middle == 79` to `section_232`
- [x] `extract_section232_rates()` extracts `semi_rate` from 9903.79.01
- [x] `06_calculate_rates.R` heading loop: gate + router + setdiff semi products out of non-semi heading lists (auto_parts 8471 overlap)
- [x] `06_calculate_rates.R` per-HTS10 `qualifying_share` × `(1 - end_use_exemption_share)` scaling
- [x] `06_calculate_rates.R` post-stacking override: restores semi heading rate after derivatives + annex (handles 8473.30.20/.51 alum-derivative overlap, rev_5+ post-annex zeroing)
- [x] 10 new tests in `tests/test_rate_calculation.R` (60/60 passing): classify_authority, extract_section232_rates, 7 integration fixtures covering Note 39(a)(7)-(9), Note 2(v)(xvi), MX/CA fent exclusion, China 60% stack
- [x] `docs/revision_changelog.md` corrected (no longer claims "normal Ch99 parsing")
- [x] `docs/assumptions.md` new §16 documenting `qualifying_share` and `end_use_exemption_share` uncalibrated-upper-bound defaults
- [x] **Aggregate ETR impact measured: +0.57pp at Jan 15→16** (14.433% → 15.003% weighted). Uncalibrated upper bound — realistic ~0.05-0.20pp after Phase 5 calibration.

### Section 122 × semi stacking (investigated 2026-04-21, no fix needed)

Note 39(a)'s exclusion list doesn't cover 9903.03 (Section 122 Phase 3), so strictly per the legal text, s122 should stack on semi products. The tracker's `nonmetal_share = 0` mechanism for 232 products zeros s122 in stacking — conceptually wrong for semi, but the output is correct anyway because **all 8 semi HTS8 prefixes are already on `resources/s122_exempt_products.csv`** (1,656 HTS8 codes from the ITA exempt list). Verified: `rate_s122 = 0` across all 2,400 semi pairs in both rev_4 and rev_5 snapshots.

Net: tracker gives the right answer (0 s122 on semi) for two independent reasons. If a future policy change removed semi products from the s122 exempt list, the stacking mechanism would still zero s122 — which would then be a bug. Defer unless that happens.

### Effective date note

Legal effective date is **Jan 15, 2026 (12:01 am EST)** per the Jan 14 proclamation. `config/revision_dates.csv` has `2026_rev_1 = 2026-01-16` (HTS JSON publication date). Pre-existing tracker convention — same as Budget Lab Yale's Tariff-ETRs historical config. Not fixed here; would be a separate revision_dates cleanup.


## Code review findings (2026-04-15) — Critical / Minor / Completed

### Critical

- [x] **Silent row multiplication from unchecked left_join** (`06_calculate_rates.R`): ~15 `left_join` operations on `rates` with no before/after row-count assertions. A duplicate key in any join table silently multiplies rows, producing incorrect rates. Add `relationship = 'many-to-one'` or post-join nrow checks.
- [x] **rowwise() on large expansion** (`06_calculate_rates.R:122-128`): `check_country_applies()` called row-by-row via `rowwise() %>% mutate()` on potentially millions of rows. Should be vectorized.

### Minor

- [x] **Unreachable guard after stop()** (`06_calculate_rates.R`): redundant `if (file.exists(...))` after `stop()` on `!file.exists(...)`. Removed dead branch.

### Completed

- [x] Fix Annex III over-broad HTS prefixes for 3 headings (fee2769, closes #5) (2026-04-15)
- [x] Extract `compute_nonmetal_share()` to deduplicate stacking logic (f83f1b6) (2026-04-15)
- [x] Add `relationship = 'many-to-one'` to 21 lookup joins in `06_calculate_rates.R` (2026-04-15)
- [x] Replace `rowwise()` expansion with pre-computed applicability mapping in `calculate_rates_fast()` (2026-04-15)
- [x] Remove module-level side effects from `06_calculate_rates.R` — pass constants as parameters (2026-04-15)
- [x] Add `tests/test_rate_calculation.R`: 50 fixture-based tests for extract_*, invariants, stacking, parsing, schema (2026-04-15)
- [x] Wire `test_rate_calculation.R` into CI (2026-04-15)
- [x] Split `helpers.R` into 5 focused modules + architecture doc + CONTRIBUTING update (2026-04-15)


## Code review follow-ups (2026-04-22) — Blocking / Required changes / Repo housekeeping

### Blocking fixes

- [x] **Fentanyl stacking docstring/code divergence** (`src/stacking.R`): docstring claimed non-China fentanyl passes through at full rate on 232 products; code scales by `nonmetal_share`. Verified against Tariff-ETRs `calculations.R:1571-1575` — code is correct, docstring + misleading "copper exception" comment updated. Memory note corrected.
- [x] **Silent fail-open on `us_auto_content_share`** (`src/06_calculate_rates.R` step 4b, `src/generate_etrs_config.R`): missing config key previously defaulted to `1.0` (full USMCA exemption — ~4.7pp CA/MX auto over-exemption). Now fail closed with actionable error.
- [x] **Hardcoded UK `'4120'` for country overrides** (`src/05_parse_policy_params.R`): 9903.81.94-99 and 9903.85.12-15 previously attributed every entry to UK. New `extract_country_specific_overrides()` helper uses `parse_countries()` + ISO→Census map with EU expansion; warns on unparseable entries.

### Required changes

- [x] **`heading_gates` fail closed**: unregistered heading names now `stop()` with list of orphans rather than silently activating on every revision.
- [x] **`section_232_headings` required**: NULL block now errors rather than silently skipping non-chapter 232 programs.
- [x] **`message('WARNING: ...')` → `warning()`**: three sites (products_file, prefixes_file, semi qualifying_shares_file) — missing resources now surface in CI.
- [x] **`max_rate_with_variance_log()` helper** (parser): 8 `max(rate)` call sites log rate divergence if a ch99 range ever introduces a different rate instead of silently picking max.
- [x] **`match_232_heading_products()` helper** (`src/06_calculate_rates.R`): extracted the ~40-line prefix-matching logic duplicated in step 4 (rate assignment) and step 5 (derivative-overlap exclusion).
- [x] **`load_232_derivative_products()` cached**: loaded once per build and passed into both `apply_232_derivatives()` and the step 5c annex fallback.
- [x] **`aluminum_derivative_{rate,exempt}`**: renamed for symmetry with `steel_derivative_{rate,exempt}` (parser return, 06_calculate_rates.R consumer, test fixture).
- [x] **`vehicle_prefixes` fragile fallback** (step 4c auto deals): vehicle/parts split now sourced from `heading_product_lists` — stable if `autos_passenger`/`autos_light_trucks` ever migrate from inline `prefixes:` to `products_file:`.
- [x] **Auto-deal classification fail-loud** (`src/05_parse_policy_params.R`): parts regex extended (`auto parts`, `light trucks` variants); unclassifiable entries warn + drop rather than silently bucketing as `auto_vehicles`.

### Repo housekeeping

- [x] Repo metadata: `CITATION.cff`, `DATA_SOURCES.md`, `SECURITY.md` (`c4a4985`).
- [x] S232 reference PDFs + `annexes_text.txt` retained in `docs/s232/`; saved-page HTM bundle removed (`5bf88c3`).
- [x] `scripts/validate_derivative_classification.R` + `scripts/verify_scenario_differences.R` committed as durable validation tooling.
- [x] `.gitignore` additions: `test_output/`, `resources/USITC - USMCA - *.xlsx`, `resources/*_diagnostic.csv`.
- [x] Deleted 4 one-off migration scripts (`patch_and_test.R`, `scripts/diff_step1_refactor.R`, `scripts/verify_step2_dense.R`, `scripts/diagnose_tpc_match_shift.R`).


---

## Alternatives unification plan (2026-06-10) — Steps 1–4 LANDED detail

**LANDED 2026-06-10 (Steps 1–4).** Discovery that reshaped the plan: the
AuthoritySpec verb/operations API the original plan assumed (`scenario_ops.R`,
`TARIFF_SCENARIO_OPS`) was deliberately DELETED in `54cc662` (no production
caller; `docs/scenarios.md` was stale). The live mechanism is config overlays
only — so everything, including counterfactuals, is now an overlay.

What landed (see `docs/scenarios.md` for the model):
- **Registry**: `src/scenario_registry.R` (`list_scenarios()`,
  `resolve_alternatives_selector()`, `build_scenario_alt_specs()`); every
  non-baseline series is `config/scenarios/<name>/{meta.yaml, overlay.yaml}`
  with `kind: alternative|counterfactual|scenario|baseline`. The 7 rebuild
  alternatives migrated from pp_override closures to overlays (the USMCA
  loaders DO read the pp keys — verified); per-variant pp now comes from
  `load_policy_params(scenario = name)`, identical to a TARIFF_SCENARIO build.
- **Counterfactuals resurrected as overlays**: new `disabled_authorities:`
  config hook — `apply_authority_disables()` in `src/rate_schema.R`, called at
  step 7g of `calculate_rates_for_revision()` (pre-stacking, so totals/shares
  recompute consistently). Six scenarios authored with their exact legacy
  `config/scenarios.yaml` semantics (no_ieepa, no_ieepa_recip, no_301, no_232,
  no_s122, pre_2025 — pre_2025 keeps 232 + legacy 301 incl. their 2025-26
  expansions, as before). Absent in baseline ⇒ byte-identical no-op.
- **One flag, one runner**: `--alternatives <names|all|alternatives|counterfactuals>`
  on `00_build_timeseries.R`; `run_alternative_series()` resolves the selector
  against the registry and dispatches through `alt_runner()`. Legacy
  `--with-alternatives`/`--rebuild-alts` kept as working aliases (the blog
  pipeline passes them) with a nudge message; unknown names now fail loud.
  Outputs already unify at `output/scenarios/<name>/` via `scenario_dir()`.
- **Tests**: `tests/test_scenario_registry.R` (35 green locally): registry
  validation, selector expansion, closure-vs-overlay pp parity for all 7
  alternatives, `apply_authority_disables()` units, counterfactual round-trips,
  and the invariant that a counterfactual pp differs from baseline ONLY in
  `disabled_authorities`.

## Phase-1 statutory corrections (2026-06-12) — full batch detail

Source: tariff-etr-eval `docs/residual_gap_deep_dive_2026-06-12.md` (items
1–6); plan = statutory fixes first (this batch, vintage N+1), then eval
re-pull + adj recalibration, THEN the Phase-2 applicability/claim shares
(pharma 232, Nairobi 9817.00.96, Japan offsets) calibrated against the
re-baselined residual. Registry of all deviations:
`docs/statutory_deviations.md` (NEW — log every share/knob there).

**Landed in this batch (all CI suites green; Slurm-validated on 14 sentinel
revisions via `~/trk_validation/p1final`):**
- **1a. §232 steel/alu product scope** (item 2, $2.5B LATE): blanket
  `['72','73']/['76']` replaced by note-derived dated lists
  (`resources/s232_metal_chapter_products.csv`, 240 prefixes; loader
  `load_232_metal_chapter_products()`); 7201/7202/7203/7204/7205/7303/7602/
  7603/7611 + excepted 7216.61/.69/.91 etc. lose the metals rate in every
  era; ch73/ch76 derivative expansion correctly date-gated (2025-03-12 /
  2025-08-18). Annex era reads in-chapter scope from the annex CSV (charging
  tiers only). **NEW FINDING: `classify_s232_annex` chapter-inference arm
  charged unmatched ch72/73/74/76 lines annex_1a 50% — incl. refined copper
  cathodes 7402–7405 from 2026-04-06** (bigger $ than scrap; invisible to the
  eval doc whose window ends Q1-2026). Inference arm removed; annex CSV is
  complete (us_note_16). Deliberately KEPT the annex_1b derivative-inference
  arm (registry S3) — flag for the next collections audit.
- **1b. Ch98 on all authorities** (item 4, $1.1B): consolidated step 6b3
  zeroes 301/301cs/s301fl/s301br/s122/201/other on the ch98 secondary-
  classification set (the v(i) ch98 subset of `ieepa_exempt_products.csv`).
  **Tripling diagnosed: §122's 10% blanket charged ~115k ch98 pairs from
  2026_rev_4 (2026-02-24)** — its note 2(aa)(i) has the standard ch98
  exemption paragraph. Plus 9802 value-basis conversion
  (`ch98_value_basis.dutiable_value_shares`: .40/.50/.60 = 0.10 repair-value;
  .80 = 1.0 UNCALIBRATED — registry B3, needs US-content share).
- **1c. Canada 40% (item 5a) root cause: 9903.01.16 transshipment-evasion
  penalty (+40%, CBP-determination-contingent) misparsed as a second Canada
  GENERAL fentanyl rate from rev_17 (2025-08-01)** — max-per-census collapse
  put statutory 40% (not 35%) on ALL ~19k Canada lines; electricity only
  showed it unscaled (usmca_share=0). Extractor now skips "transshipped to
  evade" headings (mirrors `ieepa_phase1_range` starting at 9903.02.02).
  2716 stays OFF the energy carve-out (the 9903.01.13 list is the EO 14156
  §8(a) enumeration — no electricity); collected≈0 is structural no-entry
  (eval item 5b entry-coverage flag, Phase 3).
- **1d. Korea autos** (item 6): floor deals are MFN-inclusive totals (note
  33(s) "ordinary customs duty treatment"); step 6f now recomputes §232
  auto/wood deal floors against the post-FTA base (tag `s232_deal_floor`),
  so Korea 8703 total = 15.0% exactly (was 12.56% = floor−statutory-MFN +
  KORUS-scaled base). Same machinery covers Japan/EU floors (no-ops there,
  SPI≈0).
- **1e. Floor-exempt date conditioning**: `floor_exempt_products.csv` gains
  `effective_date_start` per group (eu 2025-09-25, japan 2025-09-16, korea
  2025-12-05, swiss 2026-01-01; publication-date convention) — kills the
  ~0.12pp Apr–Sep-2025 pre-deal exemption + the Swiss Nov–Dec aircraft flip.
  **Dropped the 8 bogus `japan civil_aircraft` rows (mislabeled rail/steel
  7216.61/.69/.91, 7301.10, 7302.x, 9802.00.60)** — the Japan aircraft annex
  was never parsed; fold into the Phase-2c Japan-agreement review.

**Follow-ups created by this batch:** (i) every publish-forcing change here
requires the eval re-pull + MANDATORY adj recalibration (still pending from
552693d too); (ii) registry items B3 (9802.00.80 share), S3 (annex_1b
inference), S4 (2018-era out-of-chapter stampings 8708.10.30/.29.21 not
modeled pre-Mar-2025), F1–F7 (Phase 2/3).

## §301 exclusion headings — Phase 1 LANDED/VALIDATED/SHIPPED detail

- [x] **Phase 1 LANDED 2026-06-10: date-windowed full-line zeroing (flagged UPPER BOUND).** Exclusion headings parse to `rate = NA` ("the duty provided in the applicable subheading"), `calculate_rates_fast()` drops NA-rate pairs from the rate join, so the engine charged full §301 on China mid-exclusion (evidence: rev_9, 221/8,052 pairs dropped, 170 HTS10 lines, dominated by 9903.88.69 = note 20(vvv), e.g. `0304725000` frozen haddock at 25% in-window). What landed:
  - **Expiry machinery** (`src/rate_schema.R`): `extract_expiry_date_offset()` — "through [date]" inclusive, "on or before" inclusive, "before [date]" exclusive (normalized to LAST ACTIVE DAY, max across matches, fail-loud on unparseable); `parse_chapter99()` attaches `expiry_date_offset`; `filter_active_ch99()` expiry gate **drops NA-RATE rows only** — see the rate-bearing-expiry item below for why.
  - **Registry** `resources/s301_exclusion_headings.csv` (58 headings; regenerate via `scripts/build_s301_exclusion_headings.R`, idempotent, curator rows win): auto rows = NA-rate §301 headings with "covered by an exclusion granted by USTR" text; coverage 1.0 ONLY if the heading text carries a window (18: .50–.70 rounds), windowless → coverage 0 + NEEDS_REVIEW (32). **Validity windows are NOT in the CSV** — they're read per revision from each archive's own heading text, because USTR extends them (`9903.88.69` expiry moved 2025-05-31 → 2025-08-31 → 2025-11-29 → 2026-11-09 across revisions); CSV validity_start/_end are curator overrides only.
  - **DISCOVERY — 9903.88.21–.28 are NOT product exclusions:** US note 20(z)–(gg) makes them PERMANENT CONDITIONAL derived-rate carve-outs (apply only when the entry's rate derives from another subheading on a §301 list), windowless. Curator rows at coverage 0 — full-line zeroing them would overcorrect forever. Phase-2 calibration target.
  - **Calc hook** step 6a-excl (`src/06_calculate_rates.R`, after the §301 blanket + content-split blocks, before 6b §122 — upstream of the 6b2 `statutory_rate_301` save, so the statutory shadow and the ETRs export inherit the correction): scales `rate_301`/`rate_301_cs` by `(1 − coverage_share)` for products whose ch99_refs hit an in-window registered heading. Windows recomputed from descriptions in-hook (immune to ch99 caches predating the expiry column). Config-gated: `section_301_exclusions:` in policy_params.yaml (overlay `section_301_exclusions: ~` disables; configured-but-missing file fails loud).
  - **Timeline**: expiry mirror in the `discover_boundaries` Ch99 scan (`src/timeline.R`) — NA-rate expiries interior to a revision's interval mint `bnd_<expiry+1>` snapshots (the mid-2025 stated expiries of .69/.70 are exactly this case).
  - **Tests**: 13 new in `tests/test_rate_calculation.R` (expiry extractor units incl. real .68/.69 wording, expiry-gate semantics incl. last-active-day boundary + backwards-compat, registry safety invariants, rev_9 haddock snapshot check). Suite: 98 pass / 2 skip / 2 fail locally — the 2 fails are the KNOWN stale-local-snapshot class (rev_5 Russia + the new rev_9 haddock test against the pre-fix artifact; both green after artifact re-sync). Also fixed: `scripts/rebuild_one_revision.R` still used the pre-Plank-7 calculator signature.
  - Docs: `docs/assumptions.md` §17.
- [x] **Phase 1 VALIDATED 2026-06-10 (5/5 acceptance, hook-on vs hook-off on identical HEAD code, rev_9):** exactly 144 cells × 4 cols (`rate_301`, `statutory_rate_301`, `total_additional`, `total_rate`), China only, exactly the 144 products referencing 9903.88.69/.70, haddock `0304725000` 25%→0 (total 35%→10%), expired rounds (.66/.67/.68) inert. Validated snapshot promoted to local `data/timeseries/snapshot_2026_rev_9.rds`; suite 99/2/1 locally (1 = known stale-rev_5 Russia artifact). METHOD NOTE: diffing scratch vs the Jun-5 local published snapshot was an INVALID baseline (local artifacts predate `2724bb3` edge-case fixes — broad rate_232/s122/base_rate diffs, all pre-existing); hook-on-vs-hook-off isolates the change correctly.
- [x] **Ship Phase 1 — DONE 2026-06-11**: vintage `2026-06-10-22` (built from `40d5458`, published to the shared daily-rate-tracker dir) carries the fix. Verified in the published snapshots: haddock `0304725000` China 25%→0 in-window; exactly 144 lines snap back at the new `bnd_2026-11-10` expiry boundary (24→7.5%, 119→25%, 1→50%); China weighted ETR steps 17.71%→19.46% at Nov 10 2026 (includes a separate 16-line 0.25→1.0 scheduled §301 increase at the same date); overall weighted ETR +0.235pp at the boundary. SIDE FINDING: `manifest.json::country_code_vocabulary` says "ISO-3166-1 alpha-3" but the column is Census codes — fix the manifest writer.
