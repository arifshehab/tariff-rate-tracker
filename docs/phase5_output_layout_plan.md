# Phase 5 — Restructure published output into `actual/` + `scenarios/<name>/` (PRE-WRITE)

> ## ⚠️ DOUBLE-CHECK EVERYTHING IN THIS DOC — IT MAY BE WRONG
>
> This recipe was written **ahead of execution**, as parallel work, so:
> - **Line numbers and path lists will drift.** Every `file:line` and every hardcoded-path claim
>   below is *"go confirm this is still here"*, not a guarantee. Re-grep before editing.
> - **This is a BREAKING output change** with **external consumers** (the `tariff-etrs` repo, the
>   published NFS vintage, the git release). A wrong path constant silently produces empty output or
>   breaks a downstream model. Verify the consumer list in §5 is complete before touching anything.
> - **Where this doc and the code disagree, the code wins.**
> - Master-plan ordering: Phase 5 **"depends on 1–3, independent of 4."** It needs Phase 3's frozen
>   persisted schema (internal-only decision) to be locked. Confirm that before starting.
>
> Step 0 for any executor: re-grep the hardcoded paths in §5 and reconcile this doc with reality.

---

## ✅ UPDATE 2026-06-04 — layout flip DONE; panel re-homed; current-law vintage published

The "NOT yet started" note below is **stale**. Verified vs code:
- **The layout flip is DONE + committed (`32caf0a`).** Writers route through `src/output_paths.R`
  (daily/quality/etr → `output/actual/<section>`; scenarios → `output/scenarios/<name>`);
  `publish_internal.R` writes `<vintage>/actual/<section>` + iterates `<vintage>/scenarios/<name>`;
  the false-green scripts (`run_parity_check.R`, `submit_alt_equivalence.sh`) were fixed to the new paths.
- **The one load-bearing gap — FIXED.** The rate panel (the only thing `tariff-model` consumes) was
  published at `<vintage>/timeseries/`, but `tariff-model/src/read_rate_panel.R` reads
  `<vintage>/actual/timeseries/`. `publish_timeseries()` now writes the baseline panel under
  `actual/timeseries/` (dry-run confirmed). Added `update_latest` + `include_scenarios` params to
  `publish_internal` (default TRUE, behavior-preserving).
- **Published a current-law vintage** to the shared NFS tree (Slurm `13773853`): additive
  `2026-06-04/actual/{timeseries,daily}`, `update_latest=FALSE` (ji252's `latest` untouched),
  `include_scenarios=FALSE`. Runner `output/publish_vintage.sh`. Panel = baseline, 41 revs, 194.5M rows.
- **John's calls (PM):** publish the file but DON'T touch tariff-model (he flips the switch later);
  SKIP what-ifs for now — the scenario-panel half is gated behind the Codex 232/new-coverage bugs
  (`docs/codex_review_assessment.md`), which would otherwise ship wrong scenario numbers downstream.
- **Phase-5 remaining (deferred):** per-scenario panel emission + per-scenario `operations_recipe`
  manifests (behind the Codex fixes); activate tariff-model `rate_panel:` (John); etrs_config orphan.

---

## 🔨 EXECUTION OUTCOME / RECONCILED (2026-06-03, branch `phase0-parallel-build`)

Step 0 done (4-agent recon). **Status: bug FIXED; layout work NOT yet started (gated — see below).**
The plan's bones are right but the blast radius is **bigger** than §5 documented, and there's a real
**false-green hazard** in the acceptance scripts. Corrections below override the body where they conflict.

### ✅ Done this pass
- **`semiconductors` heading-gate bug — FIXED** at `generate_etrs_config.R:243` (added
  `semiconductors = s232_rates_check$semi_rate > 0` after `buses`). Confirmed: the authoritative list is
  `compute_heading_gates()` at `06:207-222` (11 entries); the config list (`generate_etrs_config.R:232-243`)
  was a hand-rolled COPY missing only that entry — all 10 others identical. The "two lists in 06" warning
  was a red herring: the ~210 range IS `compute_heading_gates`; the ~1342 range is just a `stop()` message.
  **Latent debt:** the copy will re-diverge on the next gate addition → replace it with a call to
  `compute_heading_gates()` when `06` is next touched (needs `06` sourced + `ch99_data` in scope; not free now).

### Reconciled path table — write sites the original §"hardcoded paths" MISSED (re-grepped, current lines)
| File | Current line | Path | Note |
|------|-------------|------|------|
| `09_daily_series.R` | `:789` (`save_daily_outputs`) | `here('output','daily')` | default param; callers don't override |
| `09_daily_series.R` | `:876` (`save_alternative_output`) | `here('output','alternative')` | call sites `:1235`,`:1341` |
| `09_daily_series.R` | `:1515` | `here('output','logs','alternatives')` | **MISSED by plan** |
| `08_weighted_etr.R` | `:845-869` (`run_weighted_etr`) | `here('output','etr')` | **MISSED + HARDCODED, no param → needs an API change, not a default flip** |
| `quality_report.R` | `:372` (`run_quality_report`) | `here('output','quality')` | **MISSED**; default param |
| `00_build_timeseries.R` | `:341`,`:715` | `here('output','logs')` | **MISSED** |
| `00_build_timeseries.R` | `:487`,`:493` | `data/processed/products_raw.csv` | **MISSED**; relative path, cwd-dependent |
| `publish_internal.R` | `:116-134`; root `:48` (`SHARED_ROOT_DEFAULT`) | reads `output/{daily,quality,etr,etrs_config,alternative}` | NFS write root confirmed |
| `publish_git.R` | `:52-56` (`RELEASE_OUTPUTS`) | reads `output/daily/*.csv` + `data/timeseries/*.rds` | |
| `generate_etrs_config.R` | `output_dir` is a **required caller-supplied arg** (no default) | — | safe; only docs/examples need updating |

### Reconciled consumer list (the §5 list was INCOMPLETE)
1. **`tariff-etrs` — LOWER risk than the plan feared.** It does NOT read the NFS vintage or `output/etrs_config`
   directly; it reads its OWN `config/historical/<date>/` tree (versioned in the etrs repo, frozen at
   2026-02-24), populated by running `generate_etrs_config.R` with a caller-supplied `output_dir`. Since that
   arg has no default, **a layout move does not break the etrs read path.** Only the regen scripts
   (`regen_from_tracker.R`, `export_historical.R`) carry Windows-local tracker paths to update.
2. **`tariff-model` — a 4th consumer the plan didn't name, and the strategic prize.**
   `tariff-model/src/read_rate_panel.R:31-57` is ALREADY coded for the Phase-5 target
   (`<root>/<vintage>/{actual|scenarios/<name>}/timeseries/rate_timeseries.{parquet,rds}`), reading the NFS
   shared root. NOT yet activated (no `model_params.yaml` has a `rate_panel` block; all scenarios still use the
   legacy `tariff_etrs` path). **Phase 5's publish side is the missing half that lets tariff-model read the
   tracker directly = the consolidation goal.** Current NFS vintages are FLAT (no `actual/`/`scenarios/`) →
   `read_rate_panel.R` would `stop()` today; Phase 5 must land in `publish_internal.R` before any scenario flips.
3. **NFS vintage** (`/nfs/roberts/project/pi_nrs36/shared/model_data/Tariff-Rate-Tracker/`) — flat today
   (`<vintage>/{daily,quality,timeseries,alternative,manifest.json}` + `latest →`). No other Budget Lab repo
   reads it (grepped all siblings). Atomic `latest →` swap = hard-binary transition, no deprecation window
   unless symlinks added.
4. **Git release** — DECISION (mine, default): keep the public `release/` layout **FLAT / non-breaking** —
   just re-point `RELEASE_OUTPUTS` sources to the new internal paths; don't mirror `actual/`/`scenarios/` into
   the public release (that would break public downloaders for cosmetics). Override only if PM wants it.

### 🚩 FALSE-GREEN HAZARD (must fix in the constants step, BEFORE flipping)
These hardcode old paths and will **silently pass** after a flip (skip missing dirs, report success):
- `scripts/run_parity_check.R:55-57` (`resolve_build_dirs` hardcodes `daily_dir = output/daily`) → the
  acceptance gate gives a FALSE GREEN.
- `scripts/submit_alt_equivalence.sh:85,108` (`cp -a output/alternative`) → empty baseline, all MISSING.
- `tariff-etrs/scripts/compare_tracker_etrs_final.R:19` (diagnostic; Windows-local `output/daily`).
Route these through the same path constants so the flip can't fool the gate.

### Other reconciled facts
- **Manifest:** `build_manifest()` (`publish_internal.R:277-311`) reusable, validated vs live NFS manifest;
  extend with an `operations_recipe` key (merge after the call — no extension point in the signature).
  **`publish_git.R:165-181` has a SEPARATE inline manifest** (different keys, no `build_manifest()` call) →
  per-scenario work must touch both, or unify first. `sections` is a positional boolean array (fragile if extended).
- **`RATE_SCHEMA` frozen** (`rate_schema.R:12-20`, 19 cols) — confirmed unchanged. ✓
- **ORPHAN:** `generate_etrs_config` is NOT called by `00_build_timeseries.R`; `output/etrs_config` is populated
  by a manual/standalone run, yet `publish_internal.R:128` copies it. Wire-up gap to resolve when migrating publish.
- **`apply_scenarios.R` still active** (the `alternative/` engine, via `run_post_build_scenarios_per_revision`,
  `00:923`); `scenario_ops.R` is pre-calculator only. The `alternative/` → `scenarios/` rename interacts with the
  Phase-7 hard-cut — coordinate; don't build two naming schemes.

### Sequencing (safe-first)
1. (done) semiconductors fix.
2. **Path-constants module** (`src/output_paths.R`) routing **every** write site above (incl. the missed ones +
   the false-green scripts) — defaults = today's paths → **byte-identical**, breaks nobody. Slurm-gate.
3. **Breaking flip** to `actual/`+`scenarios/` — OUTWARD-FACING, gated on PM go + tariff-model/tariff-etrs lockstep.
4. Per-scenario manifests → publish migration → activate tariff-model `rate_panel` → back-compat symlinks/docs.

---

## In plain language (for skimming)

Right now every build overwrites one set of output folders (`output/daily`, `output/etr`, …), and
scenario variants get dumped into `output/alternative/` with a suffix in the filename
(`daily_overall_no_ieepa.csv`). Phase 5 gives the real build its own home — `actual/` — and gives
each scenario its own folder — `scenarios/no_ieepa/`, `scenarios/no_301/`, … — each with a small
`manifest.json` saying how it was built. Cleaner to publish, cleaner for downstream tools to find
"the baseline" vs "a what-if", and it makes room for the scenario engine to emit many named
counterfactuals without colliding. The cost: several scripts hardcode today's paths, plus an
external repo reads them, so they all have to move **in lockstep**.

---

## Why Phase 5 depends on Phase 3 (and not on Phase 4)

Phase 5 only touches the **output/publish layer** — *where files land and what advertises them* —
not the calculator internals. It depends on Phase 3 solely because Phase 3 **freezes the persisted
schema** (the internal-only decision: the long resolved-program table stays internal, the persisted
snapshot keeps today's wide `rate_*`/`total_*`). Phase 5 must publish that frozen schema. It is
**independent of Phase 4** (the calc-loop collapse) entirely — so this is genuinely parallelizable
against Phase 4, and the two can land in either order.

---

## Free bug fix to grab while you're here (CONFIRMED, but re-verify)

`generate_etrs_config.R` has a heading-gate list (~lines **232–243**) that is **missing the
`semiconductors` entry** that `06_calculate_rates.R` includes (`semiconductors = s232_rates$semi_rate > 0`).
Effect: if a semiconductor 232 program is active, the ETRs config bridge silently omits it.

- `generate_etrs_config.R` ~232–243: list ends at `buses`, **no `semiconductors`**.
- `06_calculate_rates.R` ~210–220 (and the heading-config list ~1342–1350): **includes** `semiconductors`.

This is a real latent discrepancy, self-contained, and a one-line fix. It is **not strictly part of
Phase 5** — it can be fixed independently and immediately. Flagged here because Phase 5 touches this
exact file. **Re-confirm both lists before fixing** (the inventory may have mis-cited the 06 line —
there appear to be two heading-gate lists in `06`, one near the fast path ~210 and one near ~1325/1379;
make sure you compare against the authoritative one).

---

## Current output layout (re-verify against disk)

```
data/timeseries/                 rate_timeseries.rds, metadata.rds         <- upstream, NOT moved
output/
├── daily/         daily_overall.csv, by_country, by_authority, by_category (+ .parquet, .xlsx, .rds)
├── quality/       schema_check.csv, revision_quality.csv, anomalies.csv, quality_report.rds
├── etr/           *.png                                                    (if 08 built)
├── etrs_config/   <date>/{statutory_rates.csv.gz, other_params.yaml, *.yaml, mfn_rates.csv}
├── alternative/   daily_overall_<variant>.csv, by_*_<variant>.csv         (scenario variants TODAY)
└── logs/
release/           README.md, MANIFEST.json, data/*_<date>.{parquet,csv}   (git publish)
```
Published mirror (NFS): `…/shared/model_data/Tariff-Rate-Tracker/<vintage>/{timeseries,daily,quality,etr,etrs_config,alternative,manifest.json}` + `latest →` symlink.

## Target layout

```
output/
├── actual/
│   ├── daily/   quality/   etr/   etrs_config/
│   └── manifest.json                      (recipe: "baseline", build flags, git, file inventory)
├── scenarios/
│   ├── no_ieepa/   { daily/ …, manifest.json }   (recipe: which operations were applied)
│   ├── no_301/     { … }
│   └── <name>/     { … }
└── manifest.json                          (top-level registry: actual + list of scenarios)
```
Note: `manifest.json` machinery **already exists** in `publish_internal.R` (~277–310) and
`publish_git.R` (~165–177) — reuse it; don't invent a new format. The new bit is per-scenario
manifests carrying the **operations recipe** (the scenario_ops list that produced it).

---

## Hardcoded paths that must move IN LOCKSTEP (re-grep every one)

| File | ~Line | Hardcoded path | Action |
|------|-------|----------------|--------|
| `publish_git.R` | 51–57 | `RELEASE_OUTPUTS` → `output/daily/daily_*.csv`, `data/timeseries/...rds` | Point at `output/actual/...` |
| `publish_internal.R` | 116–135 | `output/{daily,quality,etr,etrs_config,alternative}` copy calls | Copy `actual/` + iterate `scenarios/*` |
| `09_daily_series.R` | ~774–828 (`save_daily_outputs`) | `output/daily` | Write under `output/actual/daily` |
| `09_daily_series.R` | ~852–916 (`save_alternative_output`), ~861 | `output/alternative` | Write under `output/scenarios/<name>/` |
| `apply_scenarios.R` | ~397 | `data/timeseries/rate_timeseries.rds` | (Being hard-cut in Phase 7 — coordinate; may be moot) |
| `00_build_timeseries.R` | ~86, 321, 582 | `data/timeseries` | Leave (upstream, not part of layout change) — **confirm** |
| `generate_etrs_config.R` | docstring ~22–23 | example reads `data/timeseries/...rds`, writes caller-supplied dir | Input is parameterized (safe); just update docs/examples |

## External consumers (the lockstep blast radius — VERIFY COMPLETE)
1. **`tariff-etrs` repo** — reads `statutory_rates.csv.gz` + `other_params.yaml` from the etrs_config
   path it's handed. If `etrs_config/` moves under `actual/`, the etrs-side path config must update
   the same day. **This is the highest-risk consumer** (separate repo, separate owner-of-record).
2. **Published NFS vintage** consumers — internal models reading `…/Tariff-Rate-Tracker/<vintage>/`.
   The vintage structure itself changes (gains `actual/` + `scenarios/`) → notify/migrate readers.
3. **Git release** consumers — public readers of `release/data/*`. Decide: keep flat release layout
   (just re-point the sources) or mirror the new structure (breaking for them too).

---

## Step-by-step recipe (gate after each; nothing ships until consumers are lined up)

0. **Reconcile.** Re-grep the §"hardcoded paths" table and the §"external consumers" list. Confirm
   Phase 3 froze the schema. Decide the release-layout question (flat vs mirrored) up front.
1. **Introduce path constants** (one module, e.g. `src/output_paths.R`) so no path is spelled inline
   twice. All current writers/readers route through it. Gate: build still writes identical files to
   identical places (constants default to today's paths).
2. **Flip the constants to the new layout** (`actual/`, `scenarios/<name>/`). Gate: a full build
   produces the new tree; diff the *file contents* against an old-layout build (paths differ, bytes
   don't).
3. **Per-scenario manifests** — extend the existing manifest writer to emit one manifest per scenario
   dir carrying the operations recipe. Gate: manifest validates, round-trips.
4. **Migrate `publish_internal.R` / `publish_git.R`** to the new tree (+ top-level registry manifest).
   Gate: published vintage has `actual/` + `scenarios/` + manifests; `latest →` still resolves.
5. **Update `tariff-etrs`** path config in lockstep (coordinate with that repo's owner). Gate: an
   end-to-end etrs build off the new layout succeeds.
6. **Back-compat**: decide symlinks (`output/daily → output/actual/daily`) and/or a deprecation window
   vs a hard cut. Document in `docs/build.md`.
7. Grab the **semiconductors** fix (§ above) if not already done separately.

## Validation gate
- **Content-identical, path-different**: same build, old vs new layout → file *bytes* match, only
  locations move. (This is a plumbing change; the numbers must not move at all.)
- `latest →` symlink resolves; manifest file inventory matches what's on disk (sha256s).
- End-to-end `tariff-etrs` build succeeds reading the new layout (the load-bearing consumer check).
- Git release readable by an external clone (smoke-test the README's documented paths).

## Open questions / risks (resolve in step 0)
- **Release layout**: flat (re-point only) vs mirror the new tree (breaking for public users)? PM call.
- **Scenario naming collisions** (synthetic-revision ids) — coordinate with the Phase-7 collision-safety
  item; don't design two naming schemes.
- **`apply_scenarios.R` is slated for hard-cut in Phase 7.** If Phase 5 lands first, don't over-invest
  in wiring its old path; if Phase 7 lands first, the `alternative/` → `scenarios/` migration is cleaner.
  Check which engine is authoritative when you start.
- Does anything *outside this repo and tariff-etrs* read `output/alternative/`? Grep the sibling repos.
