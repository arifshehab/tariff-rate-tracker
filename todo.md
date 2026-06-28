# Tariff Rate Tracker — TODO

> Resolved/closed sections live in [todo-archive.md](todo-archive.md). This file holds active work only.

## Active priorities (updated 2026-06-10: rev_10 merged + first `release/` publish; build-unification Phase 0 done)

1. **Validate the re-dated rebuild.** Revision re-dating LANDED (commit 6559c2f): `policy_effective_date` populated for 35 revisions from the change-record audit (`scripts/audit_revision_dates.R`); 2026_rev_8 dropped from the series; the `tpc_policy_revision=rev_7` override removed. The full rebuild with corrected dates has since completed (the 2026-06-09 `release/` publish is built from it, through 2026_rev_10). Acceptance checks still outstanding: (a) ~~TPC policy-aligned table~~ DIRECTION CHANGE 2026-06-10: the manual TPC alignment table is retired — external validation moves to the **external-tracker comparison database** (see its section below + `docs/external_tracker_comparison.md`); until that lands, the spot-check is the same fact (Apr 17 should move from −9.71pp to low single digits under the re-dating) verified against the TPC flow file directly; (b) `compare_etrs.R`; (c) re-run `src/revision_changelog.R` so the changelog summary table picks up corrected dates; (d) hand snapshots to tariff-etr-eval — the eval's month-weighting (`usmca_h2avg` day-weighted to months) shifts materially in Mar–May and Sep–Dec 2025.
2. **Findings from the three-model decomposition (2026-06-06, `output/model_compare/`).** (a) **8471 in the annex era:** the auto-parts applicability exclusion removed 8471 from `heading_program_products`, so from 2026_rev_5 the step-5c metals-annex override now applies — and bare `8471` is on annex_1b (aluminum) per the proclamation's own Note 16(c) list (`s232_annex_products.csv`). Production therefore charges computers 25% full-value annex_1b from Apr 6, 2026 (vs 23.76% auto-parts before the fix — levels barely moved, +0.04pp ETR). This is the literal statutory reading of the new regime and there is no post-April Census evidence yet (eval window ends Mar 2026); decide when April+ collections land — the dormant 9903.82.01 zero-metal-content carve-out or an annex-level applicability share are the natural knobs. (b) **Fix-1 universe lines are invisible to all weighted ETRs:** the GTAP weights file uses 2024-vintage HTS10 codes, so the padded `…00` 8-digit-leaf codes (Swiss watches, ch98) never match the weights join — in the three-model comparison AND in the production weighted-output path (formerly `08_weighted_etr.R`, now the output/daily path). Daily *weighted* series understate their contribution; the eval's Census-side panel is unaffected. Fix: HS8-level fallback in the weights join or a concordance pass on the weights file.
3. **Retro-window follow-ups from the re-dating.** Three legally-retroactive regimes are not modeled because their HTS text arrived weeks after legal effect: EU framework exemptions retro to Sep 1 2025 (text Sep 25, rev_24); Korea floor retro to Nov 14 2025 (text Dec 5, rev_32); rev_4's 232-derivative items (Mar 12) briefly absent Mar 7–13 (rev_4 dated at the Mar-7 USMCA carve-out; stated-date gate releases them at rev_5 Mar 14). Pattern for fixing any of these if they matter in the eval: date-bounded config override like `swiss_framework`. Also: extend the release-currency gate to cross-check NEW revisions' dates against their change records at build time so dates can't drift again.
4. ~~**Sync published rev_5 artifacts with current code**~~ **DONE 2026-06-08** — `tests/test_rate_calculation.R` now passes 92/0/0 (was 3 failures in Test 12 "Annex-era country surcharges (rev_5)" against stale artifacts); the landed Russia fix is reflected in saved outputs. All four CI smoke suites green. No further action needed here.
5. **Finish the biggest post-annex modeling gaps**: Russia clause (8) full smelter/cast origin logic, UK 95% qualifying-content blending, Annex IV exception buckets, and product-condition exemptions like 9903.81.92 are still approximated or unmodeled. (9903.82.01 zero-metal-content is now scaffolded but dormant — calibration is its own line item below.)
6. **Then clear secondary rebuild/calibration debt**: rerun the OOM-failed post-build alternatives, calibrate semi/annex/zmc assumptions, and tackle the remaining low-priority performance and cleanup items.

## Specific/compound-duty EXPOSURE flags (re-scoped 2026-06-10; was "AVE gap")

**SCOPE DECISION (user, 2026-06-10): the tracker will NOT incorporate specific
or compound duties — no AVE conversion, no salvaging the ad-valorem component.**
The tracker models statutory ad-valorem rates; non-ad-valorem MFN duties are a
documented modeling boundary. What the tracker SHOULD do is **identify the
exposed product×country cells** so downstream consumers (tariff-etr-adj η
calibration, the eval, quality reports) can see exactly which lines carry a
duty the tracker models as 0%. Any AVE conversion / unit-value work, if ever
wanted, lives on the eval side.

Background (unchanged diagnosis): `parse_rate()` (`src/helpers.R:71-99`)
returns NA for any non-`%` rate; `04_parse_products.R` only recovers NA via
parent-inheritance for EMPTY strings, so non-empty specific/compound lines
(e.g. `1901.10.16.00` = `$1.035/kg + 14.9%`) end at `base_rate = 0`. Chapter
exposure (rev_5 leaf lines): HS04 47%, HS17 38%, HS21 31%, HS22 27%, HS20 23%,
HS19 18% vs ~0% in machinery. This drives the food-complex negative η (HS19
−0.54, HS21 −0.49) — magnitude tracks value-weighted exposure. TRQ structure
(1901.90 dairy) is a sub-case. Re-frames
`docs/analysis/eta_compliance_gap_drivers.md` reason #3 (dominant, not
residual, for HS17/19/21).

**Good news (scoped 2026-06-10): the flag is half-built already.**
`parse_products()` retains `base_rate_raw` (the raw duty string) and a
`has_complex_rate` flag (`!is_simple_rate(general) && general != ''`) in the
products tibble, cached per revision in `data/timeseries/products_<rev>.rds` —
so classification needs NO archive re-parsing. Neither column currently flows
past the parse.

**DISCOVERY (2026-06-10, plan pass): latent stale-sibling inheritance bug in
`rate_stack`.** `parse_products()` (`src/04_parse_products.R:62`) only updates
the inheritance stack when a line's rate is parseable/simple/"Free" — a
COMPOUND-rated parent never updates the stack. So a statistical suffix under a
compound legal line (e.g. children of `1901.10.16`, "$1.035/kg + 14.9%") walks
the stack and can inherit an EARLIER SIBLING legal line's ad-valorem rate at
the same indent — a wrong, nonzero base_rate, distinct from the known NA→0
fill. Unquantified. Design consequence: the new type inheritance must NOT
reuse `rate_stack`; build a parallel `type_stack` updated on EVERY non-empty
`general` line (including compound), which gives correct type inheritance with
zero change to rate numbers. Fixing the rate-side bug moves numbers → separate
parity-gated change (see new item below).

**Hard constraint for the implementation: zero rate-number changes.**
Acceptance = single-revision rebuild (`scripts/rebuild_one_revision.R`, rev_5,
unweighted): all rate columns byte-identical to the current snapshot, AND
chapter exposure shares reproduce the diagnosis (HS04 ~47%, HS17 ~38%, HS21
~31%, HS19 ~18%, machinery ~0%).

- [ ] **Add `base_rate_type` to the panel** (values: `ad_valorem` / `free` /
  `specific_or_compound` / `other`), derived in `04_parse_products.R` via a
  new pure `classify_rate_type()` in `helpers.R` (next to `parse_rate()`) +
  the parallel `type_stack` above for suffix inheritance (≈59% of HTS10s are
  empty-string suffixes; a suffix under a compound parent IS exposed —
  labeling suffixes "empty" would miss most of the exposure). Eyeball
  whatever lands in `other` (expected ~empty) — verify, don't rationalize.
  Carry into the rates grid at TWO verified insertion points in
  `06_calculate_rates.R`: the base-rate join in `calculate_rates_fast()`
  (~line 192) and `ensure_dense_grid()` (~line 907: add to the products
  select AND to `EXPLICIT_SET_COLUMNS` — its column-accounting gate fails
  loud if forgotten). The other base_rate re-joins (~1310, ~1925; floor/MFN
  recomputes) don't need it. `enforce_rate_schema()` preserves extra columns
  (same lifecycle precedent as `rate_s301fl`), so schema-non-breaking.
  CACHE GUARD: existing `products_<rev>.rds` caches lack the column — fail
  loud (or re-parse) when a cached products rds has no `base_rate_type`
  (same hazard class as the stale rev_5 snapshot gotcha); regenerate locally
  via `scripts/refresh_product_caches.R`. Footprint: character col ≈ 8B/row
  → ~1.6GB at the 195M-row full-scale assemble; fine at 192GB. NOTE for the
  parity harness: snapshots gain a column — numeric-tolerance parity on rate
  columns should be unaffected, but confirm the `src/parity.R` comparator
  ignores new metadata columns before the next parity run.
- [ ] **Quality-report surface**: unweighted `pct_pairs_specific_or_compound`
  in `compute_revision_quality()` (`src/quality_report.R:72` →
  `output/quality/revision_quality.csv`, always available), plus a
  per-revision side table `output/quality/specific_duty_exposure_<rev>.csv`
  (hts10, base_rate_raw, base_rate_type, description) built from the cached
  products rds. VALUE-WEIGHTED exposure share goes in `src/diagnostics.R`
  alongside `report_universe_completeness()` (reuse its Census-weights loader
  + graceful no-weights skip; numbers come from the next cluster build).
- [ ] **Flow the flag to consumers**: add `base_rate_type` to the
  `statutory_rates.csv.gz` select in `export_statutory_rates()`
  (`src/generate_etrs_config.R`) — ETRs/tariff-etr-adj read the CSV directly,
  extra column non-breaking — so they can mask or specially treat exposed
  cells in η calibration; document the scope decision ("ad-valorem only;
  exposed cells flagged, not converted") in `docs/assumptions.md`.
- [ ] **Tests**: `classify_rate_type()` units (`Free`, `6.8%`,
  `$1.035/kg + 14.9%`, `2.4¢/kg`, empty); fixture — compound parent → suffix
  inherits `specific_or_compound`, and a simple sibling BEFORE a compound
  parent does not leak its type; integration — snapshot carries the column,
  constant across countries within hts10, `1901.10.16.00` flags as exposed.
- [ ] **Quantify the stale-sibling rate inheritance bug (then decide fix).**
  Byproduct diagnostic of the type_stack work: count suffixes whose
  type-source line ≠ rate-source line, per revision, with value weights where
  available. The fix (update `rate_stack` on compound parents too, storing NA
  so children fall to NA→0 instead of a sibling's rate) MOVES NUMBERS —
  parity-gated, do NOT bundle with the flag change. Log findings in
  `tariff_tracker_investigated_issues` memory + here.

## Build unification plan (2026-06-09) — one build, three destinations, two backends

Today the compute backend dictates the destination: the serial entrypoint
(`00_build_timeseries.R --full`) writes only repo-local (+ `release/` via
`--publish-git`); the array flow (`submit_build_array.sh --config`) writes only
the shared model_data vintage ("repo never written"). Getting all destinations
means building twice. In-process cross-revision parallelism is a stub
(`parallel_lapply_revisions` always serial); only `--parallel` alternatives are
real. `submit_build.sh`/`submit_build_core.sh` were stale untracked wrappers
passing `--publish-internal`, a flag the entrypoint silently ignores (removed
from the CLI but never errored). Target end state: **one build product, three
publishers (repo mirror / vintage / release-git), two compute backends (array =
default, serial = parity baseline), one config, one verification gate.**

- [x] **Phase 0 — hygiene. DONE 2026-06-10** (commits `711223b`, `9613097`):
  stale untracked wrappers deleted; `scripts/README.md` declares blessed entry
  points; jar335-hardcoded repo paths parameterized in `submit_build_array.sh` /
  `build_array_task.sh` / `submit_build_gather.sh` / `submit_build_full.sh`;
  `00_build_timeseries.R` errors on unrecognized CLI flags; `publish_git`
  hardened (validate-then-delete, fail loud on zero/partial publish).
- [ ] **Phase 1 — destinations as config:** `destinations:` block in the build
  config (`repo:` mirror, `vintage:` + `update_latest:`, `release_git:`); three
  thin publishers reading one canonical build tree (publish_vintage exists;
  publish_git generalized to a source root; repo-mirror new). After this,
  verify-then-publish is ONE build.
- [x] **Phase 2 — shared verification gate. DONE 2026-06-10:** verify steps
  (test suite + Russia/rev_10 sanity + NA-interval check) lifted out of
  `submit_build_verify.sh` into `scripts/verify_build.R --output-root <dir>`,
  layout-aware (repo/scratch rds vs vintage parquet — opens the parquet files
  explicitly to skip the metadata.rds sibling). Every check is now a GATE
  (the old inline checks were print-only; exit code gated solely on the test
  suite). `verify: true` in build config (default true); array finalize
  publishes with `TARIFF_UPDATE_LATEST=0`, runs verify against the vintage,
  then `publish_vintage.R --latest-only` (new flag) repoints `latest` and the
  scratch is removed — verify failure keeps the vintage for inspection,
  `latest` on the previous good vintage, and the scratch intact. Smoke-tested:
  vintage layout 10/10 PASS vs `latest` (2026-06-09-18); rds layout pending
  the in-flight serial rebuild (job 14603419).
- [ ] **Phase 3 — parallel by default:** array = default backend for real work;
  serial = golden parity baseline (keep; that's its job). Do NOT finish the
  in-process Phase-3 revision-parallel stub (array supersedes it). Fold the
  rebuild-alternatives into the array config as post-gather work units so they
  stop being a separate manual job.
- [ ] **Phase 4 — alternatives unification (planned 2026-06-10):** see next
  section.

## External-tracker comparison database (2026-06-10) — replaces the manual TPC alignment table

Full survey + verified endpoints + design: `docs/external_tracker_comparison.md`.
Decision: stop maintaining the hand-built TPC policy-aligned table; instead keep
a vintage-stamped comparison database of external tracker series under
`data/comparison/`, refreshed by fetchers, compared automatically against
`output/actual/daily/`.

- [ ] **Fetchers (`src/fetch_comparison_trackers.R`).** Browser UA mandatory
  (TPC 403s default agents). (a) Datawrapper resolver: `GET
  datawrapper.dwcdn.net/<id>/` → parse meta-refresh version → `<id>/<n>/dataset.csv`;
  version `n` = vintage key, ingest on bump. IDs: TPC `aO4iG` (daily 9-good),
  `MC81F` (weekly by tariff type), `e1Iok` (by-country snapshot); Tax Foundation
  `hn0bW` (daily-dated step series w/ event labels), `2dFbJ` (annual 1821–2026).
  (b) Treasury DTS API (daily customs deposits, `transaction_catg = "DHS -
  Customs Duties, Taxes, and Fees"`, no key). (c) PIIE ZIP HEAD-poll on
  `Last-Modified` (monthly collections ETR by country/BEC).
- [ ] **Comparison report (`src/compare_external_trackers.R`).** Tidy panel
  (date × source × series × value × vintage) + five automated overlays:
  headline daily ETR vs Tax Foundation steps + TPC type-sum; authority
  decomposition vs TPC `MC81F` (and CBP collections-by-action if scraped);
  by-country vs TPC `e1Iok` on vintage dates; 9-good daily spot-check vs
  `aO4iG`; statutory-vs-collections wedge vs DTS/PIIE (ingestion only —
  η analysis stays in `tariff-etr-adj`).
- [ ] **One-time GTA/SGEPT flow-level cross-validation.** Their public xlsx
  (CC BY 4.0, ~235k country×HS8 flows with explicit stacking formulas) is the
  closest methodological sibling but is frozen at 2025-12-23
  (pre-IEEPA-strikedown) — validate a pre-strikedown date against it; revisit
  ingestion if they refresh the file (live model is behind their MCP server).
- [ ] **Retire the old path once overlays 1–3 exist:** the per-revision TPC
  match-rate step in the build and `07_validate_tpc.R`-based acceptance checks
  point at the comparison DB instead. The private flow-level file
  (`data/tpc/tariff_by_flow_day.csv`) stays for historical flow-level
  validation — public endpoints don't include it (bilateral channel with
  McClelland/Wong for refreshes).

## Alternatives unification plan (2026-06-10) — one registry, one flag, one runner

_Steps 1–4 LANDED 2026-06-10 — registry (`src/scenario_registry.R`) + config overlays + counterfactuals as `disabled_authorities` + one `--alternatives` flag/runner + 35 registry tests. Full write-up in [todo-archive.md](todo-archive.md). Remaining open work below._

Remaining:
- [ ] **Step 5 — cluster parity + verification gate.** (a) Golden diff: run
  `--alternatives alternatives` on the cluster and confirm the migrated
  overlays reproduce the prior `--with-alternatives` outputs; then DELETE the
  deprecated `build_rebuild_alt_registry()` (09_daily_series.R) and the
  parity section of the test. (b) First-ever run of the six counterfactuals
  (`--alternatives counterfactuals`, fresh-process-per-variant fixes the
  2026-04-22 OOM class) — sanity invariants: `no_301` ETR ≤ baseline
  everywhere, `pre_2025` < baseline post-Jan-2025. (c) Fold sanity checks into
  `verify_build.R` (build-unification Phase 2) so a failed variant fails the
  build instead of message(). (d) ~~Wire `tests/test_scenario_registry.R` into
  CI~~ (DONE in a3b88d3 — ci.yml smoke job, green); still pending: add it to
  the submit_plank cluster harnesses.
- [ ] **Migrate `SCENARIO_SPECS` in `build_usmca_scenarios.R`** (the standalone
  USMCA scenario builder) onto the registry, or retire that script if
  `--alternatives` covers its use.
- [ ] **`publish_git`/`publish_vintage` read `meta.publish`** to decide which
  scenario outputs ship (today: publish behavior unchanged).
- [ ] **Collapse the kind taxonomy: fold `alternative` into `scenario`, keep
  `counterfactual`** (assessed 2026-06-10). Audit result: NOTHING in the
  build/gather/publish/manifest layers branches on alternative-vs-
  counterfactual — the array flow builds both identically as full series via
  `TARIFF_SCENARIO` (proven by the 2026-06-10-22 counterfactuals+USMCA
  vintage). The split is load-bearing in exactly two places, both selector
  plumbing in `resolve_alternatives_selector()`: the `alternatives` keyword,
  and legacy `--with-alternatives` which is *defined* as kind==alternative
  (the blog pipeline's 7-variant set). `counterfactual` stays a kind: it has
  the machine-checkable invariant (pp differs from baseline ONLY via
  `disabled_authorities`, enforced in test_scenario_registry.R) that licenses
  the decomposition reading (actual − no_X = contribution of X); the
  alternative/scenario boundary is editorial only (robustness variant vs
  hypothetical world — a description line covers it). Prereqs/sequencing: do
  this WITH the Step-5 legacy-alias deletion, and pin the blog pipeline's set
  as an explicit name list (or `meta.publish` group) BEFORE merging kinds —
  otherwise its `--with-alternatives` set silently changes.

## 232/Annex-II corrections pass (2026-06-11) — exempt-list prune + per-type share fallback + manifest

Origin: eval-side ranked review 2026-06-11 (items #1/#3 + manifest cleanup authorized; the
session that started this died on a usage limit mid-verification — state recovered from its
transcript, see auto-memory `s232_corrections_pass`).

- [x] **#1 IEEPA exempt-list prune. DONE 2026-06-11 (data correction, not a stacking fix).**
  adj #6's "derivative gate zeroes the reciprocal" diagnosis was WRONG twice over: the engine
  already stacks `recip × (1 − metal_share)` (Japan 8429.52 proves it), and the full-line zeroing
  on 8479.89.95/8419.50/8483.90/8428.90 was Annex-II *list membership*. Verified directly against
  the chapter-99 PDF text (rev_19 + 2026_rev_9, `data/us_notes/`, untracked): none of those lines
  appear in the printed note 2(v)(iii)(a) enumeration — their only mentions are civil-aircraft
  country carve-outs and §232 lists. They entered via the `df1bf3b` Tariff-ETRs yaml merge and the
  `01e8e76` rebuild expansion. `scripts/prune_ieepa_exempt_untraceable.R` (decision record in
  header; user-approved scope + outright deletion) drops **1,822 rows / ~$380B 2024 imports** in
  three buckets: untraceable residue (1,242 / $196B), §232-program members double-exempted on top
  of stacking displacement (514 / $163B — EO 14257 §3(b) is modeled via `nonmetal_share`, not the
  list), ch88 aircraft (66 / $21B — country-conditional, already in `floor_exempt_products.csv`).
  Keeps 3,230: printed-enumeration traceable (2,635), note 2(v)(iii)(b) particular articles (50),
  ch98 note (v)(i) (499), ch97/49 Berman (46). Dropped codes logged to
  `output/diagnostics/ieepa_exempt_pruned_2026-06-11.csv`. Integrity re-check during
  classification: all 552 rows matching removed prefixes (copper/wood/EO 14346) carry their end
  dates — the June-4 date-windowing is intact.
- [x] **#3 Per-type metal-share zero bug. DONE 2026-06-11.** BEA-unmatched derivative lines (e.g.
  `8483905020`) get flat aggregate `metal_share = 0.5` with ZERO-FILLED type shares
  (`load_metal_content`), and the per-type paths multiplied the 232 rate (and `nonmetal_share`)
  to zero. Fixed in both sites — `apply_232_derivatives()` scaling and `compute_nonmetal_share()`
  — to fall back to the aggregate share when the active type share is 0/NA on a tagged line.
  Regression test added (fails pre-fix): `run_tests_daily_series.R` "BEA-unmatched derivative
  falls back to aggregate share". Also catches 17 BEA-matched degenerate rows (aggregate 1.0,
  all type shares 0).
- [x] **Manifest vocabulary. DONE 2026-06-11.** `write_output.R` manifest said ISO-3166-1 alpha-3;
  column is Census country codes (`resources/census_codes.csv`).
- [x] **Validation: hook-on/off single-revision diff. DONE 2026-06-11** (rev_25 + 2026_rev_9,
  baseline worktree at `2a1763c` vs fixed tree; build job `scripts/submit_fix_validation.sh`,
  key-joined diff `~/trk_validation/diff_fix_validation.R` — both OOM the 5 GB interactive cap,
  ran as Slurm jobs). **rev_25: PASS** — 355,644 changed rows confined to the expected channels
  (rate_ieepa_recip restored on 1,595 hts10 × 238 countries; fix #3 un-zeroes 8483.90.50
  rate_232 0→0.25; ch88 0→country recip via floor path; no other columns moved).
  **2026_rev_9: zero changed cells** — correct (IEEPA recip off in the §122 regime; annex-era
  232 bypasses per-type shares). Pins from eval collections (8479.89.95 Japan 3.6%→~18.6% vs
  19.0% collected; 8419.50 5.4%→~20.4% vs 21.2%): observed 8479.89.95 → 15.5–16.3%, 8419.50 →
  18.8–19.1% — ~2–3pp under the back-of-envelope pins because the engine applies
  recip × (1 − metal_share) on these derivative lines (Japan recip lands at 13.1%/11.8–15.0%,
  not flat 15%); that displacement is the intended EO 14257 §3(b) stacking, and the residual
  vs collected goes to the adj recalibration below.
- [ ] **Batched vintage**: land this + the promoted .69/.70 §301 coverage shares in ONE published
  rebuild; then eval re-pull (~35 min) + MANDATORY adj recalibration (current negative etas absorb
  the statutory omissions; fixing statutory without recalibrating double-counts). adj side must
  also correct the mechanism section in `deal_partner_negative_eta_diagnosis.md` / open_questions
  #6 (attribution changes; the negative-eta arithmetic survives).

## Phase-1 statutory corrections off the eval residual deep-dive (2026-06-12)

_Batch LANDED + Slurm-validated on 14 sentinel revisions (1a §232 metal-chapter scope, 1b ch98 on all authorities, 1c Canada 40% transshipment misparse, 1d Korea autos floor, 1e floor-exempt date conditioning). Full write-up in [todo-archive.md](todo-archive.md)._

- [ ] **Live follow-ups:** eval re-pull + MANDATORY adj recalibration (also pending from 552693d) before/with publish; calibrate registry items B3 (9802.00.80 share), S3 (annex_1b inference), S4 (2018-era out-of-chapter stampings), F1–F7 (Phase 2/3).

## Prune audit + TPC pair-level cross-check (2026-06-12) — prune corroborated; (b)-list fix batch

Aggressive 3-agent review of the 552693d prune against vintage 2026-06-11-17, plus a pair-level
comparison against the re-uploaded TPC flow file (`data/tpc/tariff_by_flow_day.csv`, private
channel, gitignored). Full detail in auto-memory `s232_corrections_pass`.

**Verdict: the prune is sound.** Independent pdftools re-extraction of note 2(v)(iii)(a) across
all 36 chapter-99 revisions: ZERO false drops. 232 bucket: no double-charge, no timing gaps
(recomputed contributions == stored totals exactly). Magnitude reconciles to 0.00pp gap at both
2025-04-15 (+2.88pp) and 2025-12-31 (+1.26pp); pure prune effect is +2.76pp peak / +0.84pp Dec-31
(rest = fix #3 ch30 pharma 232 +0.31pp and §301 claim shares +0.13pp; the +0.14pp on 2026-06-11 is
entirely §301). TPC corroboration on dropped pairs (excl. CA/MX): within-2pp agreement Apr-17
53.5% new vs 3.8% old, Nov-17 65.8% vs 36.9%, bias → ~0 by Oct/Nov; Mar-17 pre-recip control
new==old. TPC's independent rules engine charges recip on these lines — they were never Annex II.

- [x] **(b)-list fix (THIS BATCH).** The hardcoded note 2(v)(iii)(b) list in
  `scripts/prune_ieepa_exempt_untraceable.R` had 9 of the 11 printed items — missing (b)(9)
  2009.90.40 (coconut water blends) and (b)(11) 3301.29.51 (religious essential oils) → 25 false
  drops ($487M 2024 imports; exposure window 2025-11-13→2026-02-20 only, ≈+0.001pp ETR). Restored
  to `resources/ieepa_exempt_products.csv` with start 2025-11-13; pruner re-run is a clean no-op
  (3,256 kept / 0 dropped; (b) bucket 75).
- [x] **8542.39.00.60 stat-suffix gap (THIS BATCH).** Exempt list had every other 8542.39 suffix;
  the -60 line ($0.17B, China) paid 125% at peak. Added with NA dates to match siblings (8542 is
  a printed 4-digit (iii)(a) entry, so it survives the pruner via the annex file).
- [ ] **floor_exempt_products.csv has NO date conditioning** (`06_calculate_rates.R` applies
  `floor_exempt ~ 0` unconditionally). EU (1,580 hts8) / Swiss / Korea carve-outs are exempt back
  to Apr-2025, months before the deals existed. TPC splits the mechanism exactly: Germany dropped
  pairs ON the list bias −9.1pp pre-deal, OFF the list 0.00. Netting out lines already Annex-II
  exempt (binding test vs Norway): EU $71.3B + KR + CH ≈ **0.12pp overall ETR under-charge
  Apr–Sep 2025** — largest known error in the published series. Fix = add date columns keyed to
  each deal's effective date (EU ~Sep-1, KR/CH 2025-11-14) + handle the Swiss
  exempt→charged→exempt flip (9903.02.85 adapter override, Nov-21→Dec-31 intervals).
- [ ] **Japan deal annex likely missing.** The 8 "japan civil_aircraft" floor-exempt rows are
  rail/steel codes (7216/7301/7302, 9802.00.60) under 9903.96.02 — not aircraft. TPC charges
  ~3.5% on 1,019 dropped-code Japan pairs at Oct/Nov where we charge ~18%. Needs the Japan
  agreement annex text to adjudicate (TPC may also over-exempt; their flat 50% metal share is a
  known divergence).
- [ ] **`data/census_imports_2024.csv` holds only Canada+Mexico** — if it's meant to be the full
  Census pull it's truncated (build weights `data/weights/hs10_by_country_gtap_2024_con.rds` are
  complete and unaffected). Check provenance before anything new consumes it.
- [ ] Cosmetic: annex builder truncates the one printed 10-digit entry "8505.11.0070" to
  85051100 (over-inclusive keep, harmless). §122-scope question: 22 lines that lost 232 at the
  2026-04-06 annex restructure pay zero additional in the §122 era (e.g. 9403.20 furniture) —
  pre-existing, not prune-related.

## §301 exclusion headings dropped silently — full §301 charged on excluded lines (found 2026-06-09)

_Phase 1 LANDED + VALIDATED (5/5 acceptance, rev_9) + SHIPPED (vintage 2026-06-10-22): date-windowed full-line zeroing, expiry machinery (`src/rate_schema.R`), 58-heading registry, calc hook step 6a-excl, 13 tests. Full write-up in [todo-archive.md](todo-archive.md). (The manifest country-code mislabel side-finding was fixed 2026-06-11 in the 232/Annex-II batch.)_
- [ ] **NEW (found by the expiry scan): two RATE-BEARING headings carry stated expiries that the tracker ignores** — `9903.91.04` (Biden §301 tier, "through December 31, 2025") and `9903.88.09` (vestigial 2019 §301 transition line). `filter_active_ch99()` RETAINS them by design (dropping moves numbers) and prints a NOTE each build. 9903.91.04's expiry is potentially a real un-modeled 2026 change — review whether a successor heading (9903.91.05+ tier ladder) already carries the post-2025 rate via max-per-hts8, then decide whether to enable a rate-bearing expiry gate (parity-gated).
- [ ] **Phase 2 (calibration) — module BUILT 2026-06-11, method CHANGED from the original plan.** ~~Entries filed under 9903.88.69 vs total entries (Annex II claim-share pattern)~~ — **direct heading-filing observation is IMPOSSIBLE from public data** (verified: the IMDB carries NO 9903 commodity records — only 9999.95 salvage; DataWeb commodity queries on 9903.88/.69/ch99 return nothing for China; and the eval's "Annex II 9903.01.32 channel" is itself a list-membership proxy on rate_prov, not filings). Method actually used: **realized-rate inversion** per affected HTS10×China×month — `claim_share = (stat_other + full_301 − cal_dut/con_val) / full_301`; stat_other = snapshot `total_rate − rate_301` (vintage-proof), full_301 reconstructed from ch99 parse caches (max non-NA §301 ref rate, engine-consistent, time-varying). Design + caveats: `docs/s301_exclusion_calibration.md`. Module (USMCA-style, in-repo): `scripts/build_s301_exclusion_lines.R` → `resources/s301_exclusion_lines.csv` (212 rows; .69=141 lines, .70=3, carve-outs 8–9 each); `src/calibrate_s301_exclusions.R` → `resources/s301_exclusion_claim_shares{,_by_heading}.csv` + `output/diagnostics/s301_exclusion_claims_monthly.csv`; `tests/test_s301_exclusion_calibration.R` (10/10). Months tagged covered/lapsed/partial (lapse months = retro-extension placebos). FIRST MEASUREMENT + PROMOTION (2026-06-11, user-approved): stable window 2025Q3–2026Q1 → **registry coverage_share now .69 = 0.35, .70 = 0.20 (source=curator)** — Phase 1's 1.0 overshot ~3×; 2025Q1 biased up (de minimis alive), 2025Q2 unusable (145% era), Q3/Q4/2026Q1 converge 0.34–0.39. NOT yet in any build — next rebuild moves the 144 China lines from 0% to 65%/80% of statutory §301. Per-HTS10 extension BUILT dormant: `section_301_exclusions.line_coverage_file` (6a-excl override for measured lines, heading fallback; consumed file `resources/s301_exclusion_line_coverage.csv`, 142 lines; commented out in baseline, active in scenario `s301_line_coverage`) — promote after full-build parity review (line IQR 0.15–0.73 says it's worth it). REMAINING: rev_9 rebuild validation of promoted values; eval cross-check of the inversion (handoff item 1); calibrate or dismiss the .21–.28 carve-outs (`--include-carveouts`); rerun calibration each quarter as IMDB months land (drop the contaminated-era months). RETRO CAVEAT unchanged: Phase 1 models lapses as published.

## AD/CVD: strip from collected, defer the statutory layer (decided 2026-06-08)

- [ ] **Strip AD/CVD out of the collected side (`cal_dut_mo` / `customs_duties`) before calibrating η — do NOT build the statutory `rate_adcvd` layer for now.** Decision rationale + caveats in `docs/adcvd_layer_design.md` §"Decision (2026-06-08)". Policy review: the AD/CVD *regime* is structurally unchanged (Tariff Act of 1930 deposit-at-entry, additive to MFN, in collected data but not the HTS schedule), but two 2024 Commerce final rules (Mar 25 / Dec 16 2024) broadened countervailability (transnational/Belt-and-Road subsidies, PMS, labor/env/IP) and the 2025-26 case docket is heavy — so the *levels* move, which is exactly why a static HTS×country statutory layer would be perpetually stale and the collected-strip is preferred. Implementation is **`tariff-etr-adj`-side** (calibration), not the tracker. Caveats: (a) no published HTS/country-level AD/CVD collection breakdown — strip is aggregate/by-partner only (CBP assessed figures); (b) AD/CVD shares the HS84/85/90 residual with 232-derivative under-capture, which is tracker-side (`metal_share`) and separate; (c) do exactly one — keep the `rate_adcvd` scaffold dormant, never both.

## Section 232 annex restructuring (April 2026 proclamation)

Presidential proclamation of 2 April 2026 replaces single-rate 232 with four product annexes (effective 2026-04-06). See `docs/s232/s232_metals_update_note.pdf` (SGEPT analysis).

### Annex transition result

- Pre-annex ETR: 11.12% (Apr 5, rev_4)
- Post-annex ETR: 11.79% (Apr 6, rev_5)
- Change: **+0.67pp** (vs SGEPT -0.53pp)
- The +1.2pp gap vs SGEPT is a known BEA vs calibrated-flat metal content divergence: our BEA shares produce low pre-annex effective rates for derivatives, making the move to 25% full-value a net increase. SGEPT's higher flat shares (steel 40%, aluminum 35%) make the pre-annex rates higher, so 25% is more often a reduction for them.

### Open work

Recommended order here: the rev_5 artifact sync / Russia fix has landed (active-priority #4, now DONE — `test_rate_calculation.R` green 92/0/0), so the release artifacts are in sync, and the re-dated rebuild has completed (2026-06-09 `release/` publish). Remaining: rebuild validation (active-priority #1) and the post-annex modeling/documentation items below.

**Prioritized assessment (2026-06-10), by expected ETR materiality ÷ effort:**
1. **Semi Phase-5 calibration** (below, §semiconductors) — CORRECTION 2026-06-10: the interim binary `qualifying_share` calibration ALREADY LANDED 2026-04-28 (`resources/semi_qualifying_shares.csv`: all 0 except 8471.80.4000 = 1), so the +0.57pp uncalibrated-upper-bound distortion is largely resolved. Remaining: `end_use_exemption_share` still 0.0 (uncalibrated) + empirical refinement of the binary shares.
2. ~~**UK 95% qualifying-content (9903.82.04/.05)**~~ **DONE 2026-06-10.** CORRECTION to the earlier claim: the UK reduced rates were NOT unmodeled — `uk_rate` (1a 0.25 / 1b 0.15) was applied UNCONDITIONALLY (implicit qualifying share 1.0) via the adapter's replace-mode override. What landed: `uk_content_qualifying_share` blend knob (adapter blends `q*uk_rate + (1-q)*annex_rate`); baseline 1.0 = legacy-identical; SGEPT 0.30 ships in `sgept_exemptions`. SIDE FINDING (not fixed, moves numbers): the UK override gates on chapters 72/73/76, but annex_1b (c)(vi)–(vii) derivative articles span chapters beyond the metals — the UK 1b reduced rate is likely UNDER-applied outside ch72/73/76. Needs its own scoping (the annex products CSV's metal_type is the right gate, not chapters).
3. ~~**Dormant exemption shares with SGEPT numbers**~~ **DONE 2026-06-10** — but the earlier "one-line config edit" claim was WRONG: only `us_origin_metal` had a consumer (and only in the annex_1c block); `de_minimis_weight` and `motorcycle_parts` were config scaffolds with NO code reading them. Consumers built in step 5c (zmc pattern): us_origin = 10% TARGET-TOTAL floor route per note 16(e) (floor_post_mfn semantics, verified against the Annex IV text), de_minimis = exempt-share scaling on 1b/3 excl. primary chapters (note 16(c) intro 15%-weight rule), motorcycle = exempt-share on 1b ch84/85/87 (note 16(g)). All dormant in baseline (byte-identical rev_9 verified); SGEPT estimates ship in `config/scenarios/sgept_exemptions/` (kind: scenario — NOT in the `--alternatives` selector, which is pinned to the historical 7). docs/assumptions.md §18.
4. **8471 annex_1b decision** — data-gated: wait for April+ 2026 Census collections (active-priority #2a); knobs already exist.
5. **Annex IV buckets + 9903.81.92 product-condition family** — SCOPED 2026-06-10 (see §"Annex IV scoping result" below): most buckets now modeled or dormant-knobbed; the genuine remainders are note 16(h)/(i) limited-quantity (defer), 16(k) 1c-parts end-use routes (defer, low materiality), and pre-annex 9903.81.92 (document-and-defer).
6. ~~**Russia clause (8) smelter/cast origin**~~ **DONE 2026-06-10 (document-and-defer as planned):** dormant `third_country_content_share: 0.0` knob on the Russia `country_surcharges` entry — the adapter pmax's `surcharge * share` onto all non-listed countries on the same aluminum product set when > 0. 0.0 is also the realistic value (post-2023 supply chains avoid Russian metal; CBP smelt-and-cast certs). Documented in assumptions.md §18; adapter tests cover blend + dormancy.
7. **rev_6 USMCA limited-quantity carve-out (9903.82.18/.19)** — needs quantity tracking the engine doesn't have; defer unless the eval shows a CA/MX vehicle-parts gap.

- [x] **Russia rev_5 release sync — DONE 2026-06-08** (same resolution as active-priority #4): the source fix landed (`section_232_annexes.country_surcharges` plus the post-annex `pmax()` path in step 5c) and the saved artifacts were re-synced; `tests/test_rate_calculation.R` passes 92/0/0 including Test 12 against the saved rev_5 artifact.
- [ ] **Russia clause (8) is still only partially modeled.** The April 2, 2026 proclamation covers Annex I-A/I-B/III aluminum articles or derivatives that are the product of Russia **or** where any primary aluminum was smelted in Russia **or** the article was cast in Russia. Current logic only keys on exporter country (`country == '4621'`). (NOTE: the previously-referenced `docs/s232/russia_rev5_fix_plan.md` does not exist; the related diagnosis lives in `docs/russia_surcharge_mhd_leak_fix_plan.md`.) Recommended treatment per assessment above: dormant share knob + document, don't build origin tracking.
- [x] **Narrow Russia `section_232_country_exemptions` to aluminum-only — DONE 2026-06-08** (commit `2724bb3` "Fix tariff policy edge cases"): the Russia 4621 entry now reads `applies_to: ['aluminum']` (config/policy_params.yaml ~line 278), and the annex-era `country_surcharges` block is likewise `metal_types: ['aluminum']` across annex_1a/1b/3. The local-machine `test_rate_calculation.R` check "Russia steel does NOT get the aluminum-only surcharge" is the pin for this; it passes on cluster/CI (fails locally only against the stale gitignored rev_5 snapshot).
- [x] **Document (or assign) `deriv_type` in annex-era revisions. DONE 2026-06-10** — comment approach, not sentinel. Block comment at the derivative-Ch99 gate in `apply_232_derivatives()` (`src/06_calculate_rates.R`) documents that the annex-era skip (deriv_type = NA, shares = 0 from rev_5 on) is the intended policy outcome, that `s232_annex` is the column downstream readers should use in the annex era, and WHY a sentinel must not be assigned: stacking gates per-type metal-share selection on `!is.na(deriv_type)`, and annex products are taxed full-value (`nonmetal_share = 0`), so a non-NA deriv_type would wrongly re-enable metal-content splitting. See `docs/s232/rev5_baseline_review.md` §§4-5.
- [x] **Rebuild release artifacts from HEAD — DONE** (covered by the 2026-06-08 artifact sync and the full re-dated rebuild published 2026-06-09): published outputs match the current tree; Russia snapshot tests pass on saved artifacts.
- [x] **Dynamic Ch99 parsing** in `load_annex_products()` / `extract_section232_rates()` — landed 2026-05-19 across 4 commits. `Rscript src/scrape_us_notes.R --annex` regenerates `resources/s232_annex_products.csv` by parsing Note 16(c)(i)–(x) from `data/us_notes/chapter99_<revision>.pdf` (initial parser `0d41a7b`; hardening `ed69eef` — auto-detects latest revision via `latest_local_chapter99_revision()`, derives effective_date from `policy_params.yaml::section_232_annexes.effective_date`, 25 tests in `tests/run_tests_annex_parser.R` wired into CI; methodology doc `59d2561` at `docs/s232/annex_parser.md`). Idempotent; curator entries (`source != 'us_note_16'`) win on prefix overlap so manual edge-case calls (annex_2 removals, (c)(ix) overrides) are preserved. Validated semantically against the curator baseline for rev_5 — 2652 codes assigned identically, 0 disagreements. Future Note 16 changes flow through automatically (rev_6's 9903.82.18/.19 USMCA carve-out reuses (c)(i)/(c)(iii) products that are already covered).
- [x] **9903.82.01 zero-metal-content carve-out — scaffolded** (`7250a0f`, 2026-05-19). Note 16(a) exemption for articles in (c) lists containing no aluminum/steel/copper. Added `section_232_annexes.exemptions.zero_metal_content` config block + step 5c rate-scaling branch in `06_calculate_rates.R` + 4 tests. Dormant (`aggregate_share = 0.0`); behaviorally a no-op until calibrated. **Calibration is its own item below.**
### Annex IV scoping result (2026-06-10) — note 16 bucket map

Annex IV of the April 2026 proclamation = the full replacement text of U.S.
note 16; the "exception buckets" are its conditioned subdivisions. Status:
16(a) zero-metal-content → dormant knob ✓; 16(c)-intro 15%-weight de minimis →
dormant knob ✓ (NEW); 16(d) UK 95% → qualifying-share blend ✓ (NEW); 16(e)
US-origin ≥85% 10%-target-total routes (9903.82.06–.08/.15/.23/.24) → dormant
knob, floor semantics ✓ (NEW); 16(f) non-US-origin 15%-target-total
(.10/.11/.25/.26) → already the annex_3 floor model ✓; 16(g) motorcycles →
dormant knob ✓ (NEW); 16(j) 1c USMCA 40% US-content cap (.20/.21) → modeled in
the 1c config ✓. Heading-level complements not separately modeled (.09, .12,
.14, .16, .17 — the per-heading col-1-threshold splits and "No change" routes
of (e)/(f); the floors capture the economics). Genuinely open:

- [ ] **Note 16(h)/(i): limited-quantity CA/MX steel/aluminum (9903.82.18/.19).** Commerce-authorized quantities under PP 10984 clause 13; authorization volumes are not published, the engine has no quantity tracking. DEFER until the eval shows a CA/MX primary-metals gap; the shape would be a per-country share knob calibrated to realized collections, not true quota logic.
- [ ] **Note 16(k): annex_1c parts end-use routes (9903.82.23–.26).** Ch84/85/87 parts used exclusively to manufacture ag/fixed/mobile industrial equipment get the (e)/(f) target-total floors. Low materiality (a slice of 1c parts trade, eff. 2026-06-08+). Shape if needed: an `applies_to`-style share knob on annex_1c parts mirroring us_origin_metal.
- [ ] **Pre-annex `9903.81.92` US-melted steel-derivative exemption (Mar 2025 – Apr 5 2026 window).** Same us_origin family as note 16(e) but on the PRE-annex derivative path ("duties apply to the non-steel content" for US-melted steel). Materiality tiny (~1% of derivative-steel duties for ~13 months). Document-and-defer; revisit only if the eval's 2025 §232 residuals point at it.
- [ ] **UK annex_1b coverage gate (side finding from the blend work):** the adapter's UK override gates on ch72/73/76, but (c)(vi)–(vii) annex_1b articles span other chapters — UK 1b reduced rate likely UNDER-applied outside the metal chapters. Fix = gate on the annex products CSV metal_type instead; MOVES NUMBERS (UK rows only) → parity-gated.

### Lower priority

- [x] ~~UK content share blending~~ DONE 2026-06-10 (assessment #2 above).
- [ ] Exemption share CALIBRATION (consumers all built 2026-06-10, dormant; SGEPT values ship in `config/scenarios/sgept_exemptions/`). Promote to baseline if the eval prefers the scenario; real calibration sources:
  - `us_origin_metal` (~1% per SGEPT)
  - `de_minimis_weight` (~2% per SGEPT)
  - `motorcycle_parts` (~0.1% per SGEPT)
  - `zero_metal_content` (9903.82.01 — no SGEPT estimate; would need per-prefix metal-content trade data, probably CBP entry-summary detail or industry surveys)
- [ ] Annex III sunset (Dec 2027 → I-B rate): logic in place, needs future HTS revision to test
- [ ] **Calibrate `auto_parts_subdivision_r` shares** — landed as dormant config knobs (all default 0). When set, step 5d in `06_calculate_rates.R` applies a three-way mix per Note 33(r): `rate_232 = fta × 0 + (1-fta) × [cert × floor + (1-cert) × annex_1b]`. The FTA exemption follows lines 35836-35837 (KORUS / EO 14345 imports exempt from 9903.94.44/.45/.54/.55/.64/.65 additional duty AND from 9903.82.x metals annex via the (r)(1) carve-out). Resource list is 8 prefixes (87060030, 87089210/.50/.60/.75, 87089315/.30, 87089981) at rev_6; rebuild via `scripts/build_subdivision_r_products.R` after annex updates.
  - **DataWeb does not provide direct chapter-99 granularity** (investigated 2026-05-02 via `src/download_subdivision_r_share.R`). `rateProvisionCodes` is a 2-digit aggregate, not 9903.xx-line specific.
  - **Upper-bound signals from DataWeb 2025**: `fta_exempt_shares.KR` ≤ 0.86 (SPI=KR utilization on subdiv-r ch87, $577M/$672M); `fta_exempt_shares.JP` ≈ 0 (US-Japan deal is not auto-scoped); `fta_exempt_shares.EU` = 0 structurally (no EU FTA in scope). `certified_share` (within the non-FTA slice) is undifferentiated.
  - Calibration source for certified_share: CBP entry-summary line counts (likely FOIA), industry estimates from MEMA / Auto Care Association / SAFE, or sensitivity-range defaults (e.g., set 0.5 with ±0.25 alternatives). See `tariff_tracker_investigated_issues.md`.
  - **Side gap still open:** the FTA-exempt branch only fires inside the subdiv-r blend. If a KORUS-qualifying KR import does NOT also claim subdivision (r) certification, the tracker still applies 25% annex_1b. Open question: should the FTA exemption apply to the 9903.82.x metals annex independent of subdivision (r) certification? Needs its own scoping pass.

## Section 232 semiconductor tariffs (Note 39 / 9903.79) — 2026-04-20

Flagged Apr 20, 2026: ETR shows **zero change** at 2026-01-16 (2026_rev_1 semiconductor tariff boundary). 9903.79 is parsed into ch99_data (rate=25%) but never reaches any product — no footnote on any HTS10 references 9903.79 because Note 39 scopes "semiconductor articles" in legal text rather than per-product footnotes. `snapshot_2026_rev_1.rds` has 0 of 4.74M rows with rate_other > 0; daily ETR is identical to the last digit across the rev_1 boundary (14.4333%).

The existing note in `docs/revision_changelog.md:21` — "handled through the normal Chapter 99 parsing path and do not require a separate override layer" — is wrong. The rate lands in ch99_data, but nothing links it to products. Same structural issue as Section 232 auto parts (required `resources/s232_auto_parts.txt` against US Note 33(g)).

### Note 39 legal scope (from `data/us_notes/chapter99_2026_rev_1.pdf` pp. 533–535)

- **Subdivision (b) product scope**: HTS headings **8471.50, 8471.80, 8473.30** (three headings only), AND a per-article technical gate requiring "logic integrated circuit" meeting TPP/DRAM bandwidth thresholds that target advanced AI accelerators (H100-class GPUs). Scope cannot be expressed purely in HTS codes — needs a `qualifying_share` blending parameter.
- **Subdivision (a) rate**: heading 9903.79.01 = 25% on "semiconductor articles of all countries" (country_type = `all`, parser currently emits `unknown`).
- **Subheadings 9903.79.02–09 end-use carve-outs**: USMCA (.02, via subdivision (c)), U.S. data centers >100 MW (.03), repairs/replacement (.04), R&D (.05), startups/emerging-growth-co's (.06), non-data-center consumer electronics (.07), non-data-center civil industrial (.08), U.S. public sector (.09). These are end-use, not HTS-scoped — need a separate `end_use_exemption_share` blending parameter.
- **Stacking exclusions in Note 39(a)**: semi articles are NOT subject to 9903.94.xx autos/auto parts, 9903.74.xx MHD/MHD parts, 9903.78.01 copper, 9903.85.02/.12 aluminum, or aluminum derivatives. Subchapter IV ch99 additional duties (IEEPA country-EOs) DO stack. IEEPA 9903.01.77 (Brazil) and 9903.01.84 (India) explicitly exempt semi articles per Note 2(v)(xv) and (v)(xiii). Universal IEEPA (9903.01.25) interaction still needs PDF verification.

### Deferred (Phase 5, calibration)

- [x] **Calibrate `qualifying_share` per HTS10 — interim binary calibration DONE 2026-04-28** (`resources/semi_qualifying_shares.csv`): all lines 0 except 8471.80.4000 (discrete GPU/AI cards) = 1, per the Note 39(b) TPP/DRAM gate targeting H100/H200-class accelerators. Still flagged "upper bound" in the source notes — empirical refinement via CBP trade data or SIA/SEMI estimates remains optional follow-up.
- [ ] **Calibrate `end_use_exemption_share`** — fraction of qualifying imports routed through 9903.79.03–.09 carve-outs (data centers >100MW, repairs, R&D, startups, consumer, industrial, public sector). SCOPED 2026-06-10: post interim qualifying calibration the parameter only bites on `8471.80.4000` (GPU/AI cards), whose dominant importers are hyperscalers/data centers — the .03 route alone plausibly covers a MAJORITY, so the 0.3–0.5 guess may be conservative. BEST PATH IS EMPIRICAL AND AVAILABLE NOW: the eval side can measure the realized effective rate on 8471.80.4000 (Taiwan/China) from Jan 16 – Mar 2026 Census collections; realized ÷ 25% = qualifying_share × (1 − end_use_share) directly — hand to tariff-etr-adj rather than guessing. Interim option if a sensitivity series is wanted: a small scenario overlay (e.g. 0.4); do NOT change baseline until measured.
## Code review findings (2026-04-15)

Critical and structural issues identified via full-repo code review.

### Structural

- [x] **Module-level side effects** (`06_calculate_rates.R:43-61`): policy params loaded at source time into globals; tryCatch swallows config errors. Globals only serve `calculate_rates_fast()` and `check_country_applies()`. Fix: pass `ISO_TO_CENSUS` and `CTY_CHINA` as parameters, remove module-level globals, fail loudly at call time. ~20 line change.
- [x] **No integration tests for extract_* functions**: `extract_ieepa_rates()`, `extract_section232_rates()`, `extract_section122_rates()`, `extract_ieepa_fentanyl_rates()`, `extract_usmca_eligibility()` all have zero unit test coverage. These parse raw HTS JSON at the system boundary. Highest-value test: fixture-based assertions on a known revision's JSON.
- [x] **`helpers.R` is a 1,950-line junk drawer**: 46 functions across 12+ categories. Split into `policy_params.R`, `stacking.R`, `rate_schema.R`, `data_loaders.R`, `revisions.R`. helpers.R sources them for backward compatibility.
- [ ] **`calculate_rates_for_revision()` is 1,500+ lines** (`06_calculate_rates.R`): 19 numbered steps, clearly commented. Cross-step variable dependencies (auto_products, mhd_products, heading_gates flow from step 4 into steps 4b/4c/5/7) make extraction produce worse code than inline. Correctness risks already addressed (relationship guards, nonmetal dedup, tests). **Deferred — revisit if function grows past 2,000 lines or a step needs independent testing.**

## Code review follow-ups (2026-04-22)

Second critical-code-reviewer pass over the Section 232 pipeline. Three commits
landed: `42c0cab` (blocking + required-changes), `0338405` (Phase C hardening).

### Suggestion-tier follow-ups (deferred; low priority)

- [ ] O(N·M) annex prefix-matching at `src/06_calculate_rates.R:1797` — precompute into a hash for 10-15× speedup on large-annex revisions.
- [ ] Verify `load_metal_content()` isn't re-reading the BEA CSV per build.
- [ ] `statutory_rate_232` overloaded semantics — rewritten at 4 pipeline points (pre/post deal, post-annex, post-floor-recompute); consider renaming or explicit per-stage snapshots.

## Pipeline

Recommended order here: the counterfactual rerun now lives at Alternatives unification Step 5(b); leave generic pharma shares for later.

- [ ] Generic pharma country-specific exemption shares (per TPC feedback; low priority)
  - Planning note: `docs/analysis/generic_pharma_exemption_share_plan_2026-03-24.md`
- [x] USMCA 2026 monthly refresh — DONE; see "USMCA scenario and share-loading (2026-04-20)" above (section closed 2026-05-19).
- [x] ~~**Rerun 6 OOM-failed post-build alternatives (2026-04-22).**~~ DEDUPED 2026-06-10 — this is the same work as **Alternatives unification Step 5(b)** (the live checkbox; see that section). History: the 2026-04-22 `--full --with-alternatives` run completed the main timeseries + 6 rebuild alternatives but OOM'd on the 6 post-build scenarios (`cannot allocate vector of size 705.6 Mb`); `output/alternative/*_{no_*,pre_2025}.csv` are stale (Apr 15-20). The six counterfactuals are now `disabled_authorities` overlay scenarios; regenerate with `Rscript src/00_build_timeseries.R --alternatives counterfactuals --alternatives-only` on the cluster; fresh process per variant via `--parallel --alt-workers N` avoids the old OOM.

## More-granular preference share construction (2026-04-28)

Two share-refinement items surfaced by the eval `tracker_over_report.md` and `tracker_miss_report.md` Round 3. Both are about replacing or augmenting current preference-utilization inputs with finer, IMDB-empirical signals. Neither is a rate-parsing bug; they're calibration / new-channel work.

- [ ] **Refresh DataWeb USMCA monthly shares against IMDB-realized claim shares.** `tracker_over_report.md` Action 5: ~$43.3 B of LEGIT-channel over-statement on USMCA-claimed CA/MX entries indicates the tracker's monthly DataWeb shares are systematically lower than realized claim shares for some HS10×country pairs. Drill-down by HS6×country×month comparing `resources/usmca_product_shares_*.csv` to IMDB-derived (count or value of `cty_subco = 'S'/'S+'` divided by all entries in the same HS10×country×month) will identify which pairs need refresh. Same calibration pattern as the §232 semi `qualifying_share` interim fix. Eval-side handoff is the natural place to compute the IMDB-side aggregate; tracker-side change would be ingesting the refreshed shares.
- [ ] **Expose a statutory-vs-claimable rate split for the Annex II claim-rate channel.** `tracker_miss_report.md` Round 3 concluded the bulk of the $5–7 B Pattern 1 residual is importer non-claim of 9903.01.32 (eligible-but-unclaimed Annex II exemptions). Adding this as a behavioral channel parallel to USMCA shares requires the tracker to expose, per (HS10, country, revision), both (a) the statutory rate assuming 100% Annex II claim and (b) the rate if no Annex II is claimed. The diff is the upper-bound of the non-claim channel; the eval side then ingests an IMDB-derived claim share (count or value of `9903.01.32` filings vs. `9903.01.25/.43–.75/02.xx` filings by HS6×country×month) and decomposes via that share. The `ieepa_exempt_scope: 'baseline_only'` diagnostic toggle (committed 2026-04-28) already produces the no-claim rate; making this a first-class output requires emitting both rate columns side-by-side rather than rebuilding twice.

## Low priority

- **Concordance builder**: matching may overstate splits/merges. Tighten with reciprocal-best or capped matching if needed.
- **Small-country outliers**: persistent large gaps on low-import countries (Azerbaijan -26pp, Bahrain -22pp, UAE -8pp, Georgia +14pp, New Caledonia +22pp). Not material to aggregates.

