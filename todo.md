# Tariff Rate Tracker — TODO

## Active priorities (updated 2026-06-05: revisions re-dated, rebuild in flight)

1. **Validate the re-dated rebuild (running 2026-06-05).** Revision re-dating LANDED (commit 6559c2f): `policy_effective_date` populated for 35 revisions from the change-record audit (`scripts/audit_revision_dates.R`); 2026_rev_8 dropped from the series; the `tpc_policy_revision=rev_7` override removed. Full rebuild with corrected dates in progress. Acceptance checks when it lands: (a) TPC policy-aligned table — Apr 17 should move from −9.71pp to low single digits (Apr 17 now falls in rev_10: pause + China 125%+20% + electronics exempt, the regime TPC models); Mar 17 / Jul 17 mappings also shift (now rev_5 / rev_16 windows); (b) `test_tpc_comparison.R` + `compare_etrs.R`; (c) re-run `src/revision_changelog.R` so the changelog summary table picks up corrected dates; (d) hand snapshots to tariff-etr-eval — the eval's month-weighting (`usmca_h2avg` day-weighted to months) shifts materially in Mar–May and Sep–Dec 2025.
2. **Retro-window follow-ups from the re-dating (NEW).** Three legally-retroactive regimes are not modeled because their HTS text arrived weeks after legal effect: EU framework exemptions retro to Sep 1 2025 (text Sep 25, rev_24); Korea floor retro to Nov 14 2025 (text Dec 5, rev_32); rev_4's 232-derivative items (Mar 12) briefly absent Mar 7–13 (rev_4 dated at the Mar-7 USMCA carve-out; stated-date gate releases them at rev_5 Mar 14). Pattern for fixing any of these if they matter in the eval: date-bounded config override like `swiss_framework`. Also: extend the release-currency gate to cross-check NEW revisions' dates against their change records at build time so dates can't drift again.
3. **Sync published rev_5 artifacts with current code**: rebuild `2026_rev_5`, `rate_timeseries.rds`, and `metadata.rds` so the saved release outputs reflect the landed Russia fix and `tests/test_rate_calculation.R` stops failing against stale artifacts (3 failures in Test 12 "Annex-era country surcharges (rev_5)" trace to this). Largely subsumed by priority 1's full rebuild.
4. **Finish the biggest post-annex modeling gaps**: Russia clause (8) full smelter/cast origin logic, UK 95% qualifying-content blending, Annex IV exception buckets, and product-condition exemptions like 9903.81.92 are still approximated or unmodeled. (9903.82.01 zero-metal-content is now scaffolded but dormant — calibration is its own line item below.)
5. **Then clear secondary rebuild/calibration debt**: rerun the OOM-failed post-build alternatives, calibrate semi/annex/zmc assumptions, and tackle the remaining low-priority performance and cleanup items.

## Extreme-eta review fixes (2026-06-04)

Source: `docs/tracker_review_extreme_etas.md` (eval-side Census-vs-statutory etas) + code/snapshot verification against the 2026-05-08 rebuild (all findings confirmed live, not stale). Ordered by dependency and money, not by the review doc's original ranking. Verification details in `tariff_tracker_investigated_issues.md` (memory) — two of the doc's proposed mechanisms were wrong; the items below reflect the corrected root causes.

- [x] **1. Keep 8-digit leaf HTS lines (universe gap, 473 lines).** DONE 2026-06-04 (commit "Keep 8-digit leaf HTS lines..."). `parse_products()` keeps 8-digit leaves, pads to 10 with "00", drops non-leaf 8-digit rows in a post-pass. +473 hts10 (378 ch98, 95 ch91); Swiss watches now carry the 15% framework surcharge; zero rate changes on the pre-existing universe. New validation harness: `scripts/rebuild_one_revision.R` (single-revision scratch rebuild).
- [x] **2. Un-sweep general-purpose computers from 232 auto parts ($17.6B Taiwan ch84 gap).** DONE 2026-06-04. Note 33(g) legally lists bare `8471`, but its operative scope is "parts of passenger vehicles ... and light trucks" — a laptop is not one. New `applicability_shares_file` on the auto_parts heading config (`resources/s232_auto_parts_applicability.csv`, longest-prefix match; share 0 = excluded, fractional = rate blending); interim calibration 8471 = 0. Taiwan 8471 rate_232 → 0 except the 8471.80.4000 semi GPU line. Companion resolved: 8473 lines are CORRECT as-is — Annex II names only 8473.30 and all its children are already exempt; the 20% on 8473.21/.29/.40/.50 is statutory.
- [x] **3. India Annex II inheritance + ch98 across all EOs (~$2.3B).** DONE 2026-06-04. Legal text verified: note 2(z)(ii) routes India 9903.01.84 through heading 9903.01.86 to the FULL note 2(v)(iii) list (so Annex II DOES apply to India, unlike Brazil whose 9903.01.77 has its own enumerated list); every country-EO note carries the standard ch98 claim paragraph. New `country_eo_annex_ii_inherit: ['9903.01.84']` config + ch98 channel in both IEEPA blocks of `06_calculate_rates.R`. India 3004 → 0 on all 124 lines; Brazil 3004 stays 40% (correct); India/Brazil 9801 → 0.
- [x] **4. Re-run `expand_ieepa_exempt.R` (ch97 Berman).** DONE 2026-06-04. Re-ran against a refreshed universe (`scripts/refresh_product_caches.R`): +424 codes (378 new ch98 leaves, 30 ch97, 16 ch49). Audit removals preserved (0 PV codes, 0 non-8523.51). Write-back now preserves the date-window columns.
- [x] **5. Effective-date the IEEPA exempt list.** DONE 2026-06-04 — and bigger than scoped. `scripts/build_annex_ii_dates.R` extracts the note 2(v)(iii)(a) enumeration from every chapter-99 PDF, dates each entry by first appearance using the LEGAL amendment dates from the change records (electronics 2025-04-05 retroactive; EO 14346 metals/gold 2025-09-08; ag expansion 2025-11-13), and END-dates removals (copper → 232 PP 10962, exempt through 2025-07-31; wood → 232 PP 10976, through 2025-10-13; +405 windowed entries appended that were missing entirely). Loader filters in `06_calculate_rates.R` + `generate_etrs_config.R`. Also removed 74 ch06 entries — see discoveries below.
- [x] **6. USMCA eligibility false negatives.** DONE 2026-06-04. Two real root causes: (a) `extract_usmca_eligibility()` read each 10-digit item's own `special` field, but special lives on 8-digit LEGAL lines — statistical suffixes (~59% of HTS10s) were false-negative; now inherits via a legal-line stack (mirrors base-rate inheritance) and handles 8-digit leaves. (b) The h2_average share loader mapped zero-trade pairs to share 0 and absent pairs defaulted to 0 at the join; now zero-trade → NA and application falls back HTS10 → HS8 value-weighted share → 0 (fixes 2709.00.20.10 full-10% vs sibling ≈0). Residual: 7108.12.10.17 ($576M, observed claim share 0.001 with positive trade) — likely monetary gold; needs a bullion-channel decision (below).
- [ ] **Companion (diagnostics): universe completeness check.** Census HS10 universe vs snapshot universe per revision, duty-weighted, in `diagnostics.R` — would have caught item 1 cheaply and separates modeled-zero from missing-line from concordance drift in future eta reviews.

### Discoveries from the 2026-06-04 fix pass

- **revision_dates.csv is mis-dated for rev_25–31** — promoted to active priority 2 above.
- **ch06 flowers were never on the universal Annex II.** 0603/0601/0602/0604 appear ONLY on the Switzerland/Liechtenstein framework annex (2026 notes; `floor_exempt_2026_*.csv` country_group='swiss', 1,681 HTS8). The 74 universal-list ch06 entries (ETRs-alignment inheritance) wrongly exempted flowers for ALL countries — that, not ag-carve-out retroactivity, is the review's negative-eta ch06 cluster. Removed (Swiss imports stay exempt via the floor path). 4 ch06 entries with unknown provenance left in place.
- **No Swiss product exemptions exist in the 2025 HTS text.** rev_29–32 have no Swiss annex (first appears 2026_basic, where floor files already capture it). The rev_29–32 floor files are correct as-is; Nov-Dec 2025 Swiss floor applies without product exemptions per the HTS text of those revisions. If the framework annex was legally effective ~Nov 14 via CSMS ahead of HTS publication, modeling that would need the revision re-dating pass first.
- **Floor scraper hardening:** anchor regex now accepts "As provided FOR in heading(s)" (Nov 2025 restructured wording) and `parse_floor_exempt_products()` takes a per-vintage `targets` param (`scripts/regen_floor_exempt_2025.R` shows usage; ultimately not needed for rev_29–32 but keeps the scraper usable on post-restructure vintages).
- **Note 2(v)(iii)(b) "particular articles" list (9903.02.78: Etrogs, religious items)** is universal but not extracted/dated by `build_annex_ii_dates.R`; its entries are on the exempt list via ETRs alignment with NA dates (always active). Tiny trade; acceptable approximation, noted for completeness.
- **Other no-provenance entries left alone:** ~290 ch29, ~190 ch84/85 etc. exempt entries match no (iii)(a) text but reflect deliberate TPC/CSMS-aligned breadth (generic pharma, electronics clarifications). Do not blanket-remove.
- **Gold 7108 residual (deferred):** with USMCA fixes, the remaining Canada-gold gap concentrates in 7108.12.10.17 — high trade, near-zero observed USMCA claims, near-zero collected duties. Likely monetary/bullion channel (CBP treats bullion as non-dutiable under the Sept 2025 clarification, or the trade is monetary gold outside duty scope). Needs a legal-basis decision before hardcoding an exemption.

## Section 232 annex restructuring (April 2026 proclamation)

Presidential proclamation of 2 April 2026 replaces single-rate 232 with four product annexes (effective 2026-04-06). See `docs/s232/s232_metals_update_note.pdf` (SGEPT analysis).

### Annex transition result

- Pre-annex ETR: 11.12% (Apr 5, rev_4)
- Post-annex ETR: 11.79% (Apr 6, rev_5)
- Change: **+0.67pp** (vs SGEPT -0.53pp)
- The +1.2pp gap vs SGEPT is a known BEA vs calibrated-flat metal content divergence: our BEA shares produce low pre-annex effective rates for derivatives, making the move to 25% full-value a net increase. SGEPT's higher flat shares (steel 40%, aluminum 35%) make the pre-annex rates higher, so 25% is more often a reduction for them.

### Open work

Recommended order here: rebuild release artifacts (item #1 of active priorities — currently blocking 3 tests), confirm the Russia sync in saved outputs, then finish the remaining post-annex modeling/documentation items.

- [ ] **Russia rev_5 release sync:** the source fix has landed (`section_232_annexes.country_surcharges` plus the post-annex `pmax()` path in step 5c), and a fresh `calculate_rates_for_revision()` run now restores the 200% rate for `country == '4621'` on Annex I-A/I-B/III aluminum and aluminum derivatives. But the checked-in `snapshot_2026_rev_5.rds` and `rate_timeseries.rds` still predate that fix, so `tests/test_rate_calculation.R` fails against the saved rev_5 artifact (Test 12: 3 failures, confirmed 2026-05-19).
- [ ] **Russia clause (8) is still only partially modeled.** The April 2, 2026 proclamation covers Annex I-A/I-B/III aluminum articles or derivatives that are the product of Russia **or** where any primary aluminum was smelted in Russia **or** the article was cast in Russia. Current logic only keys on exporter country (`country == '4621'`). See `docs/s232/russia_rev5_fix_plan.md`.
- [ ] **Document (or assign) `deriv_type` in annex-era revisions.** In rev_5 all rows have `deriv_type = NA` and per-type shares = 0 because `apply_232_derivatives()` gates on pre-annex Ch99 codes (9903.81.89-93, 9903.85.04/07/08, 9903.78.01) that are absent from the rev_5 HTS. This is correct-by-policy (full-value taxation replaces metal-content scaling) but arrived at accidentally through a failing gate. Either add a comment documenting the intent, or have step 5c assign a sentinel value (e.g., `deriv_type = 'annex_1a'`) so downstream readers can distinguish "no derivative classification" from "annex-era full-value regime." See `docs/s232/rev5_baseline_review.md` §§4-5.
- [ ] **Rebuild release artifacts from HEAD.** Re-run `2026_rev_5`, then recombine `rate_timeseries.rds` and `metadata.rds`, so published outputs match the current tree and the new Russia snapshot tests pass on saved artifacts.
- [x] **Dynamic Ch99 parsing** in `load_annex_products()` / `extract_section232_rates()` — landed 2026-05-19 across 4 commits. `Rscript src/scrape_us_notes.R --annex` regenerates `resources/s232_annex_products.csv` by parsing Note 16(c)(i)–(x) from `data/us_notes/chapter99_<revision>.pdf` (initial parser `0d41a7b`; hardening `ed69eef` — auto-detects latest revision via `latest_local_chapter99_revision()`, derives effective_date from `policy_params.yaml::section_232_annexes.effective_date`, 25 tests in `tests/run_tests_annex_parser.R` wired into CI; methodology doc `59d2561` at `docs/s232/annex_parser.md`). Idempotent; curator entries (`source != 'us_note_16'`) win on prefix overlap so manual edge-case calls (annex_2 removals, (c)(ix) overrides) are preserved. Validated semantically against the curator baseline for rev_5 — 2652 codes assigned identically, 0 disagreements. Future Note 16 changes flow through automatically (rev_6's 9903.82.18/.19 USMCA carve-out reuses (c)(i)/(c)(iii) products that are already covered).
- [x] **9903.82.01 zero-metal-content carve-out — scaffolded** (`7250a0f`, 2026-05-19). Note 16(a) exemption for articles in (c) lists containing no aluminum/steel/copper. Added `section_232_annexes.exemptions.zero_metal_content` config block + step 5c rate-scaling branch in `06_calculate_rates.R` + 4 tests. Dormant (`aggregate_share = 0.0`); behaviorally a no-op until calibrated. **Calibration is its own item below.**
- [ ] **Modeling gap: conditioned post-annex branches still open**
  - UK reduced rates with 95% qualifying-content condition (9903.82.04/.05)
  - 9903.82.18 / 9903.82.19 — rev_6 USMCA limited-quantity vehicle-parts carve-out (Commerce-authorized limited quantities; needs quantity-tracking logic that the current rate engine doesn't have)
  - Annex IV exception buckets / other conditioned 10% paths beyond zero_metal_content
  - `9903.81.92` and other product-condition exemptions that don't fit the current country/product binary framework

### Lower priority

- [ ] UK content share blending (`uk_content_qualifying_share`, default 30% per SGEPT)
- [ ] Exemption calibration. All four annex exemptions are scaffolded with `aggregate_share: 0.0` (dormant) in `policy_params.yaml::section_232_annexes.exemptions`; turning any of them on is a one-line config edit once shares are known:
  - `us_origin_metal` (~1% per SGEPT)
  - `de_minimis_weight` (~2% per SGEPT, applies_to annex_1b/3, excludes chs 72/73/74/76)
  - `motorcycle_parts` (~0.1% per SGEPT, applies_to annex_1b)
  - `zero_metal_content` (9903.82.01 — no SGEPT estimate; would need per-prefix metal-content trade data, probably CBP entry-summary detail or industry surveys)
- [ ] Annex III sunset (Dec 2027 → I-B rate): logic in place, needs future HTS revision to test
- [ ] **Calibrate `auto_parts_subdivision_r` shares** — landed as dormant config knobs (all default 0). When set, step 5d in `06_calculate_rates.R` applies a three-way mix per Note 33(r): `rate_232 = fta × 0 + (1-fta) × [cert × floor + (1-cert) × annex_1b]`. The FTA exemption follows lines 35836-35837 (KORUS / EO 14345 imports exempt from 9903.94.44/.45/.54/.55/.64/.65 additional duty AND from 9903.82.x metals annex via the (r)(1) carve-out). Resource list is 8 prefixes (87060030, 87089210/.50/.60/.75, 87089315/.30, 87089981) at rev_6; rebuild via `scripts/build_subdivision_r_products.R` after annex updates.
  - **DataWeb does not provide direct chapter-99 granularity** (investigated 2026-05-02 via `src/download_subdivision_r_share.R`). `rateProvisionCodes` is a 2-digit aggregate, not 9903.xx-line specific.
  - **Upper-bound signals from DataWeb 2025**: `fta_exempt_shares.KR` ≤ 0.86 (SPI=KR utilization on subdiv-r ch87, $577M/$672M); `fta_exempt_shares.JP` ≈ 0 (US-Japan deal is not auto-scoped); `fta_exempt_shares.EU` = 0 structurally (no EU FTA in scope). `certified_share` (within the non-FTA slice) is undifferentiated.
  - Calibration source for certified_share: CBP entry-summary line counts (likely FOIA), industry estimates from MEMA / Auto Care Association / SAFE, or sensitivity-range defaults (e.g., set 0.5 with ±0.25 alternatives). See `tariff_tracker_investigated_issues.md`.
  - **Side gap still open:** the FTA-exempt branch only fires inside the subdiv-r blend. If a KORUS-qualifying KR import does NOT also claim subdivision (r) certification, the tracker still applies 25% annex_1b. Open question: should the FTA exemption apply to the 9903.82.x metals annex independent of subdivision (r) certification? Needs its own scoping pass.

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

## Section 232 semiconductor tariffs (Note 39 / 9903.79) — 2026-04-20

Flagged Apr 20, 2026: ETR shows **zero change** at 2026-01-16 (2026_rev_1 semiconductor tariff boundary). 9903.79 is parsed into ch99_data (rate=25%) but never reaches any product — no footnote on any HTS10 references 9903.79 because Note 39 scopes "semiconductor articles" in legal text rather than per-product footnotes. `snapshot_2026_rev_1.rds` has 0 of 4.74M rows with rate_other > 0; daily ETR is identical to the last digit across the rev_1 boundary (14.4333%).

The existing note in `docs/revision_changelog.md:21` — "handled through the normal Chapter 99 parsing path and do not require a separate override layer" — is wrong. The rate lands in ch99_data, but nothing links it to products. Same structural issue as Section 232 auto parts (required `resources/s232_auto_parts.txt` against US Note 33(g)).

### Note 39 legal scope (from `data/us_notes/chapter99_2026_rev_1.pdf` pp. 533–535)

- **Subdivision (b) product scope**: HTS headings **8471.50, 8471.80, 8473.30** (three headings only), AND a per-article technical gate requiring "logic integrated circuit" meeting TPP/DRAM bandwidth thresholds that target advanced AI accelerators (H100-class GPUs). Scope cannot be expressed purely in HTS codes — needs a `qualifying_share` blending parameter.
- **Subdivision (a) rate**: heading 9903.79.01 = 25% on "semiconductor articles of all countries" (country_type = `all`, parser currently emits `unknown`).
- **Subheadings 9903.79.02–09 end-use carve-outs**: USMCA (.02, via subdivision (c)), U.S. data centers >100 MW (.03), repairs/replacement (.04), R&D (.05), startups/emerging-growth-co's (.06), non-data-center consumer electronics (.07), non-data-center civil industrial (.08), U.S. public sector (.09). These are end-use, not HTS-scoped — need a separate `end_use_exemption_share` blending parameter.
- **Stacking exclusions in Note 39(a)**: semi articles are NOT subject to 9903.94.xx autos/auto parts, 9903.74.xx MHD/MHD parts, 9903.78.01 copper, 9903.85.02/.12 aluminum, or aluminum derivatives. Subchapter IV ch99 additional duties (IEEPA country-EOs) DO stack. IEEPA 9903.01.77 (Brazil) and 9903.01.84 (India) explicitly exempt semi articles per Note 2(v)(xv) and (v)(xiii). Universal IEEPA (9903.01.25) interaction still needs PDF verification.

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

### Deferred (Phase 5, calibration)

- [ ] **Calibrate `qualifying_share` per HTS10** — target Nvidia H200, AMD MI325X class accelerators only meet Note 39(b) TPP/DRAM gate. Primary source: 8471.80.4000 (discrete GPU/AI cards); most other 8471/8473 HTS10s should calibrate to ~0. Source: CBP trade data or SIA/SEMI industry estimates.
- [ ] **Calibrate `end_use_exemption_share`** — fraction of qualifying imports routed through 9903.79.03–.09 carve-outs (data centers, R&D, startups, consumer, industrial, public sector). Probably 0.3–0.5 based on AI/datacenter capex share.
### Section 122 × semi stacking (investigated 2026-04-21, no fix needed)

Note 39(a)'s exclusion list doesn't cover 9903.03 (Section 122 Phase 3), so strictly per the legal text, s122 should stack on semi products. The tracker's `nonmetal_share = 0` mechanism for 232 products zeros s122 in stacking — conceptually wrong for semi, but the output is correct anyway because **all 8 semi HTS8 prefixes are already on `resources/s122_exempt_products.csv`** (1,656 HTS8 codes from the ITA exempt list). Verified: `rate_s122 = 0` across all 2,400 semi pairs in both rev_4 and rev_5 snapshots.

Net: tracker gives the right answer (0 s122 on semi) for two independent reasons. If a future policy change removed semi products from the s122 exempt list, the stacking mechanism would still zero s122 — which would then be a bug. Defer unless that happens.

### Effective date note

Legal effective date is **Jan 15, 2026 (12:01 am EST)** per the Jan 14 proclamation. `config/revision_dates.csv` has `2026_rev_1 = 2026-01-16` (HTS JSON publication date). Pre-existing tracker convention — same as Budget Lab Yale's Tariff-ETRs historical config. Not fixed here; would be a separate revision_dates cleanup.

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

## Code review findings (2026-04-15)

Critical and structural issues identified via full-repo code review.

### Critical

- [x] **Silent row multiplication from unchecked left_join** (`06_calculate_rates.R`): ~15 `left_join` operations on `rates` with no before/after row-count assertions. A duplicate key in any join table silently multiplies rows, producing incorrect rates. Add `relationship = 'many-to-one'` or post-join nrow checks.
- [x] **rowwise() on large expansion** (`06_calculate_rates.R:122-128`): `check_country_applies()` called row-by-row via `rowwise() %>% mutate()` on potentially millions of rows. Should be vectorized.

### Structural

- [x] **Module-level side effects** (`06_calculate_rates.R:43-61`): policy params loaded at source time into globals; tryCatch swallows config errors. Globals only serve `calculate_rates_fast()` and `check_country_applies()`. Fix: pass `ISO_TO_CENSUS` and `CTY_CHINA` as parameters, remove module-level globals, fail loudly at call time. ~20 line change.
- [x] **No integration tests for extract_* functions**: `extract_ieepa_rates()`, `extract_section232_rates()`, `extract_section122_rates()`, `extract_ieepa_fentanyl_rates()`, `extract_usmca_eligibility()` all have zero unit test coverage. These parse raw HTS JSON at the system boundary. Highest-value test: fixture-based assertions on a known revision's JSON.
- [x] **`helpers.R` is a 1,950-line junk drawer**: 46 functions across 12+ categories. Split into `policy_params.R`, `stacking.R`, `rate_schema.R`, `data_loaders.R`, `revisions.R`. helpers.R sources them for backward compatibility.
- [ ] **`calculate_rates_for_revision()` is 1,500+ lines** (`06_calculate_rates.R`): 19 numbered steps, clearly commented. Cross-step variable dependencies (auto_products, mhd_products, heading_gates flow from step 4 into steps 4b/4c/5/7) make extraction produce worse code than inline. Correctness risks already addressed (relationship guards, nonmetal dedup, tests). **Deferred — revisit if function grows past 2,000 lines or a step needs independent testing.**

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

## Code review follow-ups (2026-04-22)

Second critical-code-reviewer pass over the Section 232 pipeline. Three commits
landed: `42c0cab` (blocking + required-changes), `0338405` (Phase C hardening).

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

### Suggestion-tier follow-ups (deferred; low priority)

- [ ] O(N·M) annex prefix-matching at `src/06_calculate_rates.R:1797` — precompute into a hash for 10-15× speedup on large-annex revisions.
- [ ] Verify `load_metal_content()` isn't re-reading the BEA CSV per build.
- [ ] `statutory_rate_232` overloaded semantics — rewritten at 4 pipeline points (pre/post deal, post-annex, post-floor-recompute); consider renaming or explicit per-stage snapshots.

## Pipeline

Recommended order here: finish the USMCA refresh path, then rerun the OOM-failed post-build alternatives, and leave generic pharma shares for later.

- [ ] Generic pharma country-specific exemption shares (per TPC feedback; low priority)
  - Planning note: `docs/analysis/generic_pharma_exemption_share_plan_2026-03-24.md`
- [ ] USMCA 2026 monthly refresh — see "USMCA scenario and share-loading (2026-04-20)" above.
- [ ] **Rerun 6 OOM-failed post-build alternatives (2026-04-22).** Full rebuild via `--full --with-alternatives` completed the main timeseries (58.5 min) and the 6 rebuild alternatives (usmca_annual/monthly/2024/dec2025, metal_flat, dutyfree_nonzero) successfully, but the 6 post-build scenarios `no_ieepa`, `no_ieepa_recip`, `no_301`, `no_232`, `no_s122`, `pre_2025` all failed with `cannot allocate vector of size 705.6 Mb` on `filter(revision == 'rev_X')` — R ran out of memory after accumulating state across the ~5-hour run. The corresponding `output/alternative/*_{no_*,pre_2025}.csv` files are stale (dated Apr 15-20, pre-dating the semi tariff work). Rerun option: a fresh R process per scenario. Either restart the machine and re-run `--full --with-alternatives`, or run each failed scenario in its own Rscript invocation (prototype: `apply_scenario(ts, name, scenarios_path) |> build_daily_aggregates(...) |> save_alternative_output(...)`). Each should take a few minutes with fresh memory.

## More-granular preference share construction (2026-04-28)

Two share-refinement items surfaced by the eval `tracker_over_report.md` and `tracker_miss_report.md` Round 3. Both are about replacing or augmenting current preference-utilization inputs with finer, IMDB-empirical signals. Neither is a rate-parsing bug; they're calibration / new-channel work.

- [ ] **Refresh DataWeb USMCA monthly shares against IMDB-realized claim shares.** `tracker_over_report.md` Action 5: ~$43.3 B of LEGIT-channel over-statement on USMCA-claimed CA/MX entries indicates the tracker's monthly DataWeb shares are systematically lower than realized claim shares for some HS10×country pairs. Drill-down by HS6×country×month comparing `resources/usmca_product_shares_*.csv` to IMDB-derived (count or value of `cty_subco = 'S'/'S+'` divided by all entries in the same HS10×country×month) will identify which pairs need refresh. Same calibration pattern as the §232 semi `qualifying_share` interim fix. Eval-side handoff is the natural place to compute the IMDB-side aggregate; tracker-side change would be ingesting the refreshed shares.
- [ ] **Expose a statutory-vs-claimable rate split for the Annex II claim-rate channel.** `tracker_miss_report.md` Round 3 concluded the bulk of the $5–7 B Pattern 1 residual is importer non-claim of 9903.01.32 (eligible-but-unclaimed Annex II exemptions). Adding this as a behavioral channel parallel to USMCA shares requires the tracker to expose, per (HS10, country, revision), both (a) the statutory rate assuming 100% Annex II claim and (b) the rate if no Annex II is claimed. The diff is the upper-bound of the non-claim channel; the eval side then ingests an IMDB-derived claim share (count or value of `9903.01.32` filings vs. `9903.01.25/.43–.75/02.xx` filings by HS6×country×month) and decomposes via that share. The `ieepa_exempt_scope: 'baseline_only'` diagnostic toggle (committed 2026-04-28) already produces the no-claim rate; making this a first-class output requires emitting both rate columns side-by-side rather than rebuilding twice.

## Low priority

- **Concordance builder**: matching may overstate splits/merges. Tighten with reciprocal-best or capped matching if needed.
- **Small-country outliers**: persistent large gaps on low-import countries (Azerbaijan -26pp, Bahrain -22pp, UAE -8pp, Georgia +14pp, New Caledonia +22pp). Not material to aggregates.

---

## Resolved

<details>
<summary>BEA metal derivatives review (2026-04-06)</summary>

Five issues confirmed via code review (see `docs/analysis/section_232_review_memo_2026-04-06.md`):
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
