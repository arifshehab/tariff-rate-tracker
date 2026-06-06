# Master-fix integration into `theseus` (2026-06-06)

Two follow-ups after Pass-1 of the spec-driven refactor completed, both on `theseus`:

1. **Wire the inline floor math through `apply_rate_semantics()`** — the one loose
   end from Plank 0 (the helper was built + tested but never called).
2. **Integrate the substantive fixes that landed on `master` after we branched**
   (`9f9837d`, 2026-06-04) — the six "extreme-eta" policy fixes + the revision
   re-dating — then quantify the daily-rate impact and **increment the golden**.

## 1. `pmax` → `apply_rate_semantics` (parity-safe)

Commit `32e77b8`. The five inline floor sites in `06_calculate_rates.R` (IEEPA-recip
floor initial `1159` + new-pairs `1225` + 6d post-MFN recompute `2564`; §232 annex_3
floor initial `2012` + 6e recompute `2578`) now call
`apply_rate_semantics(value, 'floor_post_mfn', base)`. Byte-identical by construction
(the helper's only delta over inline `pmax` is NA→0, unreachable here: `base_rate` is
`coalesce`d to 0 and the guards/masks keep it non-NA). **Parity gate GREEN 47/47** vs
`tests/golden/9f9837d`.

## 2. Master-fix integration (golden-changing)

`origin/master` (`5cb951d`) was 23 commits ahead of theseus's merge-base, a parallel
fix line. theseus is the parity-locked refactor of the *pre-fix* code, so these fixes
had to be **ported into the refactored structure**, not cherry-picked. John's own
three-model decomposition (`39f53d5`) + `todo.md` gave the expected magnitudes (used
as an oracle). Ports (each a separate, revertible commit; each matched against master's
diff and parse-checked):

| Commit | Fix | Effect |
|---|---|---|
| `7df20b3` | fix1 — keep 8-digit leaf HTS lines (`04`) | +473 hts10; ~0 on existing universe |
| `8d8caef` | re-dating (`6559c2f`) — policy-aligned dates; drop 2026_rev_8 | timing channel; 43→42 revs |
| `eb145ba` | fix4+5 — IEEPA exempt re-expand + date-window | stops retroactive exemptions |
| `b3dd1b5` | fix6 — USMCA eligibility + HS8 share fallback | CA/MX big movers |
| `70b6b97` | fix2+7 — auto-parts applicability + India country-EO + statutory shadow | 8471 un-sweep; India pharma → 0 |

**Smoke build (`2026_rev_2`) reproduced John's per-product validation exactly:**
`USMCA HS8 fallback filled 6237 of 20787`; 23 excluded Taiwan 8471 lines with
`rate_232=0` / `statutory_rate_232=0.237625`; the 8471.80.4000 GPU line stays 0.25;
India 3004 → 0; Brazil 3004 stays 40%.

### Calls made (flag for review)

- **fix4+5 mapping correction:** the fix-mapping agent said the date-window filter was
  ETR-export-only; in fact **master's 06 date-filters the universal exempt list** (theseus
  previously filtered only the *country-EO* list). Ported the filter into the 06
  universal-exempt loader — load-bearing for the panel.
- **NOT ported:** `scrape_us_notes.R`'s Nov-2025 regex hardening. It's a
  resource-regeneration scraper (not in the build path; its regenerated outputs were
  copied verbatim), and porting risked clobbering a theseus-side edit. Zero golden impact.
- **fix7 step-7d** depends on `rebate_deduction` (06:1802) — confirmed in scope at the
  step-7d site (before stacking).

## Daily-rate impact (NEW vs golden `9f9837d`, by calendar date, 730 days)

`scripts/report_master_fix_impact.R` (output in `output/master_fix_impact/`). A by-date
comparison captures the **total** effect (policy + timing combined); separating the two
needs John's three-model run.

- **Overall mean total rate: +14.751pp → +14.403pp (−0.349pp** time-averaged).
- **Biggest day-level swings = the re-dating (timing):** early-Apr 2025 −8.56pp
  (reciprocal regime shifted later → those days now sit in rev_5/6, not rev_7/8);
  mid-May −1.96pp.
- **By authority:** §232 −0.187pp (8471 un-sweep + date-windowing), ieepa −0.023pp,
  fentanyl −0.021pp, s122 +0.010pp, 301 −0.002pp.
- **By country:** Canada **−3.97pp**, Mexico **−3.38pp** (USMCA share fix); India
  **−1.71pp** (country-EO Annex-II inheritance); China **+1.86pp**, HK +2.25, Macao
  +2.53 (date-windowing correctly stops the retroactive electronics exemption in
  pre-Apr-5 revisions); ~−0.36pp universal tail (8471 un-sweep + 8-digit-leaf dilution).

These reproduce John's documented magnitudes (CA −5.3 / MX −4.0pp at the 2026_rev_2
snapshot; the time-averaged numbers here are smaller because early-2025 dates predate
most 232 programs).

## Golden incremented

New on-disk golden **`tests/golden/70b6b97/`** (the golden tree is gitignored — local
artifact, not committed): 42 snapshots, 4 daily CSVs, `rate_timeseries.rds`, manifest
(`git_sha 70b6b97`, new `policy_params_md5 5ccadd69…`, `use_policy_dates: true`).
**This replaces `9f9837d` as the parity reference** for future runs at this code state.
`9f9837d` is retained for provenance / decomposition.

## Open / not done (for John)

- **Policy-vs-timing decomposition not run.** The total (D−A) is reported + frozen. To
  split the −0.349pp into policy (B−A) vs timing (D−B) channels, run John's three-model
  tooling (`scripts/compare_three_models.R`, needs a `B` build = current code × old
  dates via `--use-hts-dates`). Not done — the total was the deliverable for the golden.
- `scrape_us_notes.R` regex hardening (above) — port if the scraper is re-run on a
  post-restructure vintage.
- Pre-existing Russia §232 aluminium-surcharge invariant failures (documented in the
  plan) are orthogonal and unchanged.
