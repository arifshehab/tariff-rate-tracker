# Merge plan: `taiwan-rev9-gz-archives` → AuthoritySpec branch

**Date:** 2026-06-04
**Author:** analysis for the AuthoritySpec migration (`phase0-parallel-build`)
**Source branch:** `origin/taiwan-rev9-gz-archives` (John Iselin / ji252), tip `a25d052`
**Target branch:** `phase0-parallel-build` (the full AuthoritySpec refactor, Phases 0–8 + Codex fixes)
**Fork point (merge-base):** `8840217` "docs: Zenodo setup recipe" — **2026-05-21**, i.e. *before* the AuthoritySpec refactor. Both branches descend from this commit.

> **Key decision (John, 2026-06-04): DATA STAYS EXTERNAL.** The canonical repo does **not** commit HTS archives. We keep our `.gitignore` of `data/hts_archives/*.json.gz`; we take the branch's *code/config*, not its committed archive blobs. This changes the merge mechanics — see [§6](#6-the-data-external-decision-and-what-it-means-mechanically). A naïve `git merge` would commit ~30 MB of archives + PDFs into history and must NOT be used.

---

## 1. Executive summary

This is a **manageable merge with no architectural conflict.** The branch is four cleanly-separable commits adding (a) gzip archive storage, (b) two new HTS revisions, (c) a Taiwan civil-aircraft Section-232 exemption, and (d) self-contained legacy-ETR inputs. None of it fights the AuthoritySpec design:

- The **gzip read path is inherited for free** by our parallel build and the archives are **lossless** copies — so the existing 41-revision parity golden stays valid; baseline numbers don't move.
- The **Taiwan exemption is a downstream post-process** on the rate table (zeroes `rate_232`), agnostic to our spec-driven 232 source — it merges as a near-verbatim insert, no spec re-homing.
- The only real complexity is (i) honoring "data external" during the merge, (ii) extending the golden to the **2 new revisions** (43 total), and (iii) ~four textual conflict resolutions.

**Conflict surface (files touched by both branches):** `.gitignore`, `src/00_build_timeseries.R`, `src/05_parse_policy_params.R`, `src/06_calculate_rates.R`, `src/helpers.R`, `src/preflight.R`. Everything else the branch changes, we never touched → applies cleanly.

---

## 2. What the branch contains — 4 commits

| Commit | Title | Concern | Recommendation |
|---|---|---|---|
| `6aa5863` | Ingest HTS 2026 rev_8/rev_9, store archives gzipped, add Taiwan rev_9 policy | gzip + new revisions + Taiwan config | **Take (code/config only — not the archive blobs)** |
| `40cf65b` | Add HTS release-currency gate to the build run | build guard on the *monolithic* path | **Optional** (no effect on our parallel build) |
| `5b86fbb` | Fix Taiwan note-35(c) aircraft exemption: clean product list + gate on metals annex | new 232 economics | **Take** |
| `a25d052` | Make build self-contained for weighted-ETR inputs | legacy-ETR input regeneration | **Skip** (redundant; feeds the vestigial ETR path) |

The four commits map to **independent concerns**, which is why cherry-picking (not a blanket merge) is the recommended mechanism — it lets each be accepted/dropped on its own and keeps the data blobs out.

---

## 3. Interaction analysis vs. the AuthoritySpec code

### 3.1 gzip archives — inherited for free, and lossless ✅

- **Format:** archives are stored as `hts_<year>_<rev>.json.gz`. Reading is gz-aware via two functions in `src/revisions.R` (which **we did not touch** — take wholesale):
  - `resolve_json_path()` (branch `src/revisions.R` ~L170): tries `.json.gz` **first**, falls back to raw `.json`, else errors. → **Backward-compatible**: our existing local `.json` archives still read fine.
  - `list_available_revisions()` (branch `src/revisions.R` ~L148): pattern widened to `hts_<year>.*\.json(\.gz)?$` and de-duped so a revision present as both `.json` and `.json.gz` counts once.
  - `jsonlite::fromJSON()` decompresses `.json.gz` transparently — no separate gunzip step added to the parsers.
- **Our build inherits it with zero extra wiring:** `scripts/build_revision.R:74` → `build_revision_snapshot()` (`src/00_build_timeseries.R` ~L93/96) → `resolve_json_path()` → `fromJSON()`. The enumerator `scripts/list_revisions.R:27` → `get_available_revisions_all_years()` → `list_available_revisions()`. Both are exactly the functions the branch gz-ifies. **Merging `revisions.R` is sufficient.**
- **Lossless (verified):** the committed `.gz` blobs decompress **byte-identical** to our working `.json` (checked `hts_2025_basic`, `hts_2025_rev_1`, `hts_2026_rev_7`; md5-identical for `hts_2025_rev_32`). → **The 41-revision parity golden remains valid; baseline numbers will not move.**
- `src/02_download_hts.R` (+269) adds a USITC *export-endpoint* download fallback + `gzip_file()` for **future** downloads (the static USITC host now 403s). This is download-time machinery, irrelevant to reading committed/local archives.

### 3.2 New revisions rev_8 / rev_9 — golden must grow to 43 ⚠️

- Exactly **two** new revisions, **2026 only**, registered in `config/revision_dates.csv` (+2 rows):
  - `2026_rev_8` — **2026-05-22** — "No Chapter 99 or rate changes vs rev_7 (editorial only)." Expected to be ≈ rev_7 in output.
  - `2026_rev_9` — **2026-05-28** — Taiwan added to the 15% floor framework (232 auto parts `9903.94.66-.69`, wood `9903.76.24`, civil-aircraft exemption `9903.96.03`).
- **Our parallel array would pick them up automatically** (it enumerates `load_revision_dates()$revision` ∩ available archives). Result: **43 revisions, not 41.**
- **Implication:** the parity golden (`data/timeseries/`, 41 revs) must be re-captured at 43. rev_8 should validate ≈ byte-identical to the rev_7 region; **rev_9 is genuinely new** (Taiwan policy + exemption) and is validated as new behavior, not against the old golden.

### 3.3 Taiwan civil-aircraft 232 exemption — low risk, no spec re-homing ✅

US Note 35(c) / heading `9903.96.03` exempts Taiwan civil-aircraft components from the **Section-232 metals annex** (not the reciprocal tariff). Implementation:

- **`src/06_calculate_rates.R` — new "step 7c"** (branch ~L2682), inserted *after* USMCA (step 7) and *before* stacking (step 8):
  ```r
  aircraft_cfg <- pp$section_232_aircraft_exemption
  if (!is.null(aircraft_cfg) && isTRUE(aircraft_cfg$enabled) &&
      '9903.96.03' %in% ch99_data$ch99_code) {
    tw_aircraft <- load_232_aircraft_exempt_taiwan()
    cty_tw <- pp$country_codes$CTY_TAIWAN
    annex_232_mask <- if ('s232_annex' %in% names(rates)) !is.na(rates$s232_annex) else FALSE
    air_mask <- rates$country == cty_tw &
      substr(rates$hts10, 1, 8) %in% tw_aircraft &
      rates$rate_232 > 0 & annex_232_mask
    if (sum(air_mask) > 0) {
      rates$rate_232[air_mask] <- 0
      if ('s232_annex' %in% names(rates)) rates$s232_annex[air_mask] <- NA_character_
    }
  }
  ```
- **Why it's low-risk:** it reads the *already-computed* `rates$rate_232` / `rates$s232_annex` columns and zeroes them — it is **agnostic to how `rate_232` was produced.** Our refactor changed the *source* of `rate_232` (spec-driven), but the columns still exist identically. So this block drops into our `06` near-verbatim, alongside the new-coverage seeder (step 7b) and the F5 `statutory_rate_other` re-sync — **independent columns, no clash.** No need to push this into the spec/`extract_section232_rates`.
- The `9903.96.03`-present gate makes it **self-dating to rev_9+**; the `s232_annex`-set gate ensures it only removes a *metals-annex* duty, never a wood/auto/MHD 232.
- **Supporting pieces (all clean adds — we didn't touch these files):**
  - `load_232_aircraft_exempt_taiwan()` in `src/data_loaders.R` (+20).
  - `resources/s232_aircraft_exempt_taiwan.csv` (120 rows: `hts8, ch99_code, source`). **Commit this** — it's a curated policy resource, not bulk data.
  - `config/policy_params.yaml`: `CTY_TAIWAN: '5830'`, `iso_to_census: TW: '5830'`, and the `section_232_aircraft_exemption` block (`enabled`, `country: TW`, `products_file`). Clean add (we never edited `policy_params.yaml`).
  - `src/scrape_us_notes.R` (+7): comment-only clarification. Clean add.
- **Known gap (documented in the branch, not ours to fix here):** the parallel carve-outs for the all-country general case and EU/UK/JP/KR (Note 35(a)/(b), `9903.96.01/.02`) are **not modeled**. The branch also adds a `06` comment (~L912) noting Taiwan is intentionally *not* in the floor-exemption group map (that path would wrongly zero the reciprocal).

### 3.4 Release-currency gate — no interference with the parallel build ✅

- `check_release_currency()` (`src/02_download_hts.R`) queries USITC `releaseList` and classifies: `up_to_date` / `one_ahead` (auto-fetchable) / `behind_manual` (**stop**) / `unknown` (network fail → proceed with warning).
- **Hooks only into the monolithic CLI** (`src/00_build_timeseries.R` `if (sys.nframe()==0)` block, branch ~L645-661, behind a new `--skip-release-check` flag), before `download_missing_revisions()`.
- **`build_revision.R` and `build_gather.R` never enter that block**, so the gate **never fires in the parallel array.** Caveat: it makes a live network call — keep it behind the flag / `sys.nframe()` guard; do **not** lift it into `build_revision.R`.

### 3.5 Self-contained weighted-ETR inputs — redundant, recommend skip ⚠️

- Commit `a25d052` adds `write_policy_inputs()` to `src/05_parse_policy_params.R` and a call in `build_full_timeseries()` (`00` "Hunk B") to regenerate `ieepa_country_rates.csv`, `usmca_products.csv`, `products_raw.csv`.
- **Redundant on our side:** our `build_revision_snapshot()` already writes `products_raw.csv` per revision (`src/00_build_timeseries.R` ~L517-528), and the monolithic block already sources `08_weighted_etr.R` / `run_weighted_etr()`.
- **Feeds the vestigial path:** `ieepa_country_rates.csv` + `08_weighted_etr.R` were assessed as **vestigial** (tariff-model and tariff-etrs each compute their own ETR; nothing downstream consumes the tracker's ETR output). See the parity-harness work.
- **Recommendation: skip Hunk B.** If ever wanted, it also requires pulling `write_policy_inputs()` from `05`, and it only helps the legacy monolithic run (the array uses `build_gather.R`, not `build_full_timeseries`).

---

## 4. Conflict surface — file-by-file

| File | We changed? | Branch changed? | Risk | Resolution |
|---|---|---|---|---|
| `src/revisions.R` | **No** | Yes (gz-aware resolve/list) | **None** | **Take branch wholesale** — load-bearing gzip support |
| `src/data_loaders.R` | No | Yes (+20, Taiwan loader) | None | Clean add |
| `src/02_download_hts.R` | No | Yes (+269) | None | Clean add (download-time only) |
| `src/01_scrape_revision_dates.R` | No | Yes (+5 gz-aware) | None | Clean add |
| `src/03_parse_chapter99.R`, `src/04_parse_products.R` | No | Yes (small) | None | Clean add |
| `src/scrape_us_notes.R` | No | Yes (+7 comment) | None | Clean add |
| `config/policy_params.yaml` | No | Yes (+16 Taiwan) | None | Clean add |
| `config/revision_dates.csv` | No | Yes (+2 rows) | None | Clean add |
| `resources/s232_aircraft_exempt_taiwan.csv` | No | Yes (new, 120 rows) | None | Clean add (**commit it** — policy resource) |
| `src/06_calculate_rates.R` | **Yes (big)** | Yes (+39 step 7c) | **Medium** | Insert step 7c before stacking, beside seeder/F5 |
| `src/00_build_timeseries.R` | **Yes (big)** | Yes (+45, 2 hunks) | **High** | Graft release-gate hunk; **drop** ETR-inputs hunk |
| `src/05_parse_policy_params.R` | **Yes** | Yes (write_policy_inputs) | Low | Different region; skip Hunk-B helper |
| `src/helpers.R` | Yes (source lines) | Yes (gz pattern) | Low | Different regions; take branch's gz pattern |
| `src/preflight.R` | Yes (drop scenarios.yaml) | Yes (gz pattern) | Low | Different regions; take branch's gz pattern |
| `.gitignore` | **Yes** (added `*.json.gz` ignore) | Yes (comment) | **Decision** | **Keep our ignore — data external** (see §6) |

Notes:
- `src/helpers.R`: the branch's only change is `get_latest_hts_archive()`'s pattern (`…\.json$` → `…\.json(\.gz)?$`). That function has **zero callers** in `src/`/`scripts/` on HEAD (dead code) and returns a single max-mtime file, so `.json`+`.json.gz` co-existence is harmless. Take it for consistency.
- `src/preflight.R`: the branch widens an archive-count pattern; cosmetic (preflight report only).

---

## 5. Per-commit merge plan (recommended: cherry-pick)

Cherry-pick onto a throwaway branch off `phase0-parallel-build`, resolving as below. **Stage code/config only — never the archive blobs (§6).**

1. **`6aa5863` (gzip + rev_8/9 + Taiwan config)**
   - Take: `src/revisions.R` (wholesale), `src/01_scrape_revision_dates.R`, `src/03`, `src/04`, `config/revision_dates.csv` (+2), `config/policy_params.yaml` (Taiwan block + `CTY_TAIWAN` + `TW` iso), `src/helpers.R` / `src/preflight.R` (gz patterns — keep our other edits).
   - **Do NOT commit:** `data/hts_archives/*.json.gz` (43 files), the change-record PDFs. Keep `.gitignore` ignoring `*.json.gz` (§6).
2. **`5b86fbb` (Taiwan exemption)**
   - Take: `src/06_calculate_rates.R` step 7c (insert before stacking), `src/data_loaders.R` (`load_232_aircraft_exempt_taiwan`), `resources/s232_aircraft_exempt_taiwan.csv` (commit), `src/scrape_us_notes.R` comment, the `06` floor-group comment.
3. **`40cf65b` (release gate)** — *optional.* If taken: graft the gate + `--skip-release-check` flag into our **current** `00` `sys.nframe()` block; keep it inside the guard so the array never triggers it.
4. **`a25d052` (self-contained ETR inputs)** — **skip** (redundant; vestigial path). If taken later, also port `write_policy_inputs()` from `05`.

---

## 6. The "data external" decision and what it means mechanically

**Decision:** the canonical repo does **not** carry HTS archives; data lives outside git (local/gitignored, sourced per-workspace). This is the *opposite* of the branch's intent (it commits the `.gz` so the repo is self-contained).

**Consequences for the merge:**

1. **Keep our `.gitignore` line** `data/hts_archives/*.json.gz` (and the existing `*.json` ignore). Resolve the `.gitignore` conflict in **our** favor. Do **not** adopt the branch's "commit the archives" approach.
2. **A plain `git merge` is wrong** — it would add the 43 `.gz` blobs (+ change-record PDFs, ~30 MB) as tracked files (gitignore does not retroactively untrack files a commit explicitly adds). Use cherry-pick and **unstage the data blobs** before committing, e.g. after each pick:
   ```bash
   git reset HEAD 'data/hts_archives/*.json.gz' 'data/source_documents/**/*.pdf'
   git checkout -- .gitignore   # keep our ignore
   # verify nothing under data/ is staged:
   git status --short -- data/
   ```
3. **Local build data must be sourced separately** (this is the real cost of "external"):
   - The 41 existing revisions: we already have them locally as `.json` (gitignored). `resolve_json_path()` falls back to `.json`, so **no action needed** — the gz-aware code reads our local `.json` fine.
   - **rev_8 / rev_9 (new):** their archive content is *only* in ji252's branch (as committed `.gz`). Copy them into our local gitignored workspace **without committing**, e.g.:
     ```bash
     git show origin/taiwan-rev9-gz-archives:data/hts_archives/hts_2026_rev_8.json.gz \
       > data/hts_archives/hts_2026_rev_8.json.gz
     git show origin/taiwan-rev9-gz-archives:data/hts_archives/hts_2026_rev_9.json.gz \
       > data/hts_archives/hts_2026_rev_9.json.gz
     # (gitignored => stay untracked; resolve_json_path picks them up)
     ```
     Or obtain them from ji252's repo / the external data store, per the team's external-data convention.
4. **Change-record PDFs (`data/source_documents/**`):** treated as external too (reference docs, regenerable). Do not commit. (Sub-decision — flag if the team wants reference PDFs versioned; they are not build inputs.)
5. **`resources/s232_aircraft_exempt_taiwan.csv` IS committed** — it is a hand-curated policy input (like other `resources/`), not bulk data.

> **Bottom line:** merge brings in **code + small config/resource files**; the HTS archives (incl. rev_8/9) and PDFs stay external/local. The gz-aware code is backward-compatible with our local `.json`, so nothing breaks.

---

## 7. Golden rebuild + validation plan

The merge changes the revision *set* (41 → 43) and adds new behavior (Taiwan, rev_9), so the parity golden must be refreshed and the new behavior validated.

1. **Pre-merge sanity (optional):** confirm rev_8 ≈ rev_7. After sourcing rev_8/9 locally, build rev_8 and diff its snapshot against rev_7's policy region (the branch claims "editorial only").
2. **Rebuild the golden at 43 revisions** via the parallel array (`scripts/list_revisions.R` will now emit 43) → `data/timeseries/` (or a candidate dir).
3. **Parity vs. the old 41-rev golden:** the 41 pre-existing revisions must stay **byte-identical** (the `.gz` are lossless). Run the existing slice / full sweep (`output/validate_specs_*.sh`) restricted to the 41 — confirms gzip + the merge didn't move baseline.
4. **Validate the 2 new revisions as new:**
   - rev_8: expect ≈ rev_7 (editorial).
   - rev_9: **new numbers** — Taiwan on the 15% floor + the 232 aircraft exemption. Sanity-check the exemption with a focused proof: for Taiwan × the listed aircraft HTS8s in rev_9, `rate_232 == 0` and `s232_annex == NA`, while non-Taiwan and non-aircraft rows are unaffected; confirm those rows fall into the "without 232" stacking branch (reciprocal still applies). Mirror the style of `output/check_codex_copper.R`.
5. **Run the Codex scenario gate + unit suite** unchanged — the Taiwan post-process must not perturb the scenario ops (`set_rate`/`add_program`) proofs or baseline byte-identity.
6. **Re-publish** the rate panel (now 43 revs) once validated, if a fresh vintage is wanted downstream.

---

## 8. Open decisions / risks

- **[DECIDED] Data external** — keep our `.gitignore`; do not commit archives. (§6)
- **[DECISION] Release-currency gate** — take it (harmless, behind a flag) or skip? It does not affect the parallel build either way.
- **[DECISION] Change-record PDFs** — confirm external (recommended) vs. versioned.
- **[RISK] `00` graft** — our `00` is heavily restructured (≈1001 lines vs the branch's 807). The release-gate hunk must be grafted into *our current* `sys.nframe()` block, not by taking the branch's surrounding lines. The ETR-inputs hunk should be dropped.
- **[RISK] rev_9 is unparitied new behavior** — there is no golden for it; it must be validated by inspection of the Taiwan exemption effect, not by byte-identity.
- **[SCOPE] Taiwan carve-out is partial** — only Note 35(c) (Taiwan); the all-country and EU/UK/JP/KR cases (35(a)/(b)) are not modeled. Inherited as-is; note for the policy backlog.

---

## 9. Quick reference — key locations

- Fork point: `git merge-base phase0-parallel-build origin/taiwan-rev9-gz-archives` → `8840217`.
- gzip read: `src/revisions.R` `resolve_json_path()` / `list_available_revisions()` (branch).
- Our build entry: `scripts/build_revision.R:74` → `build_revision_snapshot()` (`src/00_build_timeseries.R` ~L93/96) → `resolve_json_path()` → `fromJSON()`.
- Enumeration: `scripts/list_revisions.R:27` → `get_available_revisions_all_years()` → `list_available_revisions()`.
- Taiwan exemption: `src/06_calculate_rates.R` step "7c" (~L2682 on branch) + `config/policy_params.yaml` `section_232_aircraft_exemption` + `resources/s232_aircraft_exempt_taiwan.csv` + `src/data_loaders.R::load_232_aircraft_exempt_taiwan`.
- Release gate: `src/02_download_hts.R::check_release_currency` + `src/00_build_timeseries.R` `sys.nframe()` block (~L645-661 on branch).
- Skip (redundant): `a25d052` — `write_policy_inputs()` in `src/05_parse_policy_params.R` + `00` "Hunk B".
