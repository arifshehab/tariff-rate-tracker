# Parallel Full Pipeline — Implementation Plan (v2)

**Date:** 2026-05-09
**Supersedes:** `docs/parallel_full_pipeline_plan.md` (v1, 2026-04-24)

## Why a revision

v1 correctly identified that revision-level parallelism is the right granularity
for the main rate-build loop, but it was written before two things became clear:

1. **Alternatives, not the main build, dominate wall clock.** The main full
   rebuild is ~1 h. The six rebuild alternatives are ~9 h sequentially.
   Last night's `--with-alternatives --publish` run (job 11201313) timed out
   at the 5 h walltime partway through the third of six alternatives.
2. **The Slurm cluster has much more memory than v1 assumed.** Production
   builds run with 192 GB allocations on the `day` partition. v1's
   16 GB / 32 GB / 64 GB worker-count guidance was sized for laptops and
   does not match how this package is actually run here.
3. **Most alternatives recompute work that does not depend on what they vary.**
   Four of the six alternatives (`usmca_annual`, `usmca_monthly`, `usmca_2024`,
   `usmca_dec2025`) only change `pp$USMCA_SHARES`, which is applied as the
   final transformation in `calculate_rates_for_revision()`. Every step before
   that is identical to the main build.

This revision keeps v1's safety-first design but reorders the phases to attack
the actual bottleneck first, adds an HPC profile, and adds a "skip redundant
work" path that compounds with parallelism.

## Goals (unchanged from v1)

- Optional, opt-in parallel mode; serial path remains the default.
- Preserve correctness, reproducibility, recoverability.
- Treat worker count as a memory decision, not a CPU decision.
- Cross-platform (Windows / macOS / Linux), so prefer `multisession`
  over `mclapply` in the default code path.

## Where time actually goes (measured 2026-05-09)

```
Main build                ~1 h    (41 revisions, ~1.3 min each on average)
Post-build (daily/ETR/QR) ~7 min
Alternatives (6 total)    ~9 h    (~85-90 min each, sequential)
  - usmca_annual          ~85 min
  - usmca_monthly         ~85 min
  - usmca_2024            ~85 min
  - usmca_dec2025         ~85 min
  - metal_flat            ~85 min
  - dutyfree_nonzero      ~85 min
Total                     ~10 h
```

A single alternative is, internally, roughly:

```
re-parse JSON + ch99 + products       ~7 min
re-extract IEEPA / §232 / USMCA       ~7 min
calculate_rates_for_revision x 41     ~50 min
aggregate_snapshots_per_revision      ~25 min
```

The first three of those are largely **redundant with the main build** —
the JSON, ch99, and products parses are deterministic given the archive
file, and the USMCA-only alternatives re-run rate calc identically up to
the very last transformation (`src/06_calculate_rates.R:2501-2594`).

## Recommendation summary

Three independent levers, in priority order:

1. **Cross-alternative parallelism (process-level).** Run multiple
   alternatives concurrently as separate R processes. Linear speedup,
   no semantic change, memory-bound.
2. **Per-revision parallelism (inside main build and inside each alt).**
   Fan out the 41-revision loop across workers. Linear speedup until
   memory or I/O dominates.
3. **Skip redundant work.** Reuse cached `ch99_<rev>.rds` and
   `products_<rev>.rds` in alternative builds; later, persist a
   "pre-USMCA" rate snapshot so USMCA-only alternatives become a thin
   re-application step.

(1) and (2) compose multiplicatively; (3) compounds further.

Not a goal for v1 of this work: inner-loop parallelism inside
`calculate_rates_for_revision()`. Big refactor, uncertain payoff,
keep for later.

## Constraints and notes (still apply, refreshed)

### 1. Memory dominates CPU

Confirmed by recent runs:

- Job 11189086 (2026-05-08): OOM at 96 GB allocation.
- Job 11201313 (2026-05-09): peak RSS 139 GB at 192 GB allocation, fine.

Per-revision rate calculation peaks around 30-40 GB at the largest 2026
revisions (4.7M product-country pairs, expanded grids). Each concurrent
worker — whether running an alternative or a revision — needs its own
copy of that working set.

Practical caps for the `day` partition with 192 GB:

- ~4 concurrent alternatives, **OR**
- ~4 concurrent revision workers within one alternative,
- but **not both at once** without further refactor.

### 2. Cross-platform default; HPC fast path opt-in

The repo runs on Windows, macOS, and Linux. Default backend stays
`future` + `multisession` (PSOCK clusters under the hood). On the
Slurm/Linux cluster, `multicore` (fork) is faster and uses less memory
for read-mostly worker state — make it available behind an explicit
`--backend multicore` flag, not the default.

### 3. Shared writes stay single-writer

Workers may only write **revision-scoped** or **alternative-scoped**
files. The coordinator owns:

- `data/timeseries/rate_timeseries.rds`
- `data/timeseries/metadata.rds`
- combined daily / ETR / quality outputs
- the structured build log

### 4. Logger needs a worker-safe mode

`src/logging.R` is single-target / single-file. For phase 1+:

- coordinator writes the canonical structured log
- workers write per-worker side logs (`output/logs/build_<ts>_w<N>.log`)
- coordinator stitches into the canonical log in revision order on
  worker completion

### 5. CPU oversubscription

Cap BLAS / OMP threads to 1 in worker processes whenever parallel mode
is enabled. The submit script already does this for the top-level R
process; the parallel helper must propagate it.

### 6. Combined-timeseries downstream remains a trap

Same as v1: weighted ETR and quality report still load the full
185 M-row `rate_timeseries.rds`. Snapshot-first refactor is independent
of parallelism and ships on its own track (Phase 4).

### 7. Incremental mode stays serial in v1

`--start-from` + `--parallel` falls back to serial with a clear message.

## User interface

Add to `src/00_build_timeseries.R`:

- `--parallel` — enable parallel mode (auto-resolves workers).
- `--workers N` — explicit override; validated against safe bounds.
- `--alt-workers M` — concurrent alternatives (defaults to
  `min(n_alternatives, floor(mem_gb / 40))`).
- `--backend {multisession,multicore}` — backend selection
  (default: `multisession`; `multicore` Linux-only and only with `--parallel`).

If `--parallel` is passed with `--start-from`, fall back to serial with
a message.

## Worker count guidance

Replace v1's flat table with a memory-aware rule plus an HPC profile:

| Memory available | Default revision workers | Default alt workers |
|------------------|--------------------------|---------------------|
| 16 GB            | serial                   | serial              |
| 32 GB            | 2                        | 1                   |
| 64 GB            | 3                        | 2                   |
| 128 GB           | 4                        | 3                   |
| 192 GB+ (Slurm)  | 4                        | 4                   |

Auto-selection caps revision workers and alt workers separately and
**never multiplies them** (no nested fanout) without an explicit override.
The auto-resolver logs the resolved values and the rationale.

## Architecture

### A. New helper module: `src/parallel.R`

Same as v1 — backend setup, worker resolution, `parallel_lapply_revisions()`,
log routing.

Add an `alt_runner()` helper that takes a list of `(variant_name,
pp_override)` and runs them concurrently with one R process per
alternative. This is mostly a wrapper around `future::future()` or
`callr::r()` — the alternatives are completely independent.

### B. Extract `build_revision_snapshot()`

Same as v1. Pure function, returns metadata, writes revision-scoped
artifacts.

The same function should be reused by `build_alternative_timeseries()`.
Today the alt path duplicates the rev loop body inline
(`src/09_daily_series.R:946-975`); after extraction, it becomes
`parallel_lapply_revisions(build_revision_snapshot, revs, pp_override = ...)`.

### C. Cached parse reuse for alternatives

When `--with-alternatives` is run after a successful main build:

- alts read `ch99_<rev>.rds` and `products_<rev>.rds` from
  `data/timeseries/` instead of re-parsing JSON
- alts read pre-extracted IEEPA / §232 / USMCA-eligibility caches
  if they exist; otherwise re-extract and cache for the next alt

Saves ~7-10 min per alternative; non-trivial when alternatives run
concurrently because each saved minute multiplies by `n_alts`.

### D. Pre-USMCA snapshot (for the four USMCA-only alts)

`calculate_rates_for_revision()` writes two snapshots when in
"alt-friendly" mode (controlled by a new `policy_params` flag,
default off):

- `snapshot_<rev>.rds` — final, USMCA-applied (today's behavior)
- `pre_usmca_<rev>.rds` — same rates **before** the USMCA pass, plus
  `usmca_eligible` / `s232_usmca_eligible` flags and the joined
  `usmca_share` source columns

USMCA alternatives short-circuit the rate calc entirely:

```r
build_usmca_alt <- function(pp_usmca, variant_name) {
  for (rev_id in revs) {
    pre <- readRDS(pre_usmca_path(rev_id))
    rates <- apply_usmca_pass(pre, pp_usmca)   # ~5-10s, vs. ~50s full calc
    saveRDS(rates, alt_snapshot_path(variant_name, rev_id))
  }
  aggregate_snapshots_per_revision(...)
}
```

Per-alt time drops from ~85 min to ~10-15 min (the aggregation step is
the new floor). Combined with concurrent alternatives, the full alt
phase fits in well under 30 min.

### E. Final assembly stays serial

Bind into `rate_timeseries.rds`, write `metadata.rds`, mirror to
`shared/model_data/...` — all single-coordinator. Same as v1.

## Phased plan

### Phase 0 — Scaffolding (no behavior change)

- Add `src/parallel.R`.
- Add `future`, `future.apply`, `parallelly`, `callr` to optional deps
  in `src/install_dependencies.R`.
- Add `--parallel`, `--workers`, `--alt-workers`, `--backend` flags;
  flags off by default.
- Worker resolution helper with the memory-aware table above.
- Logger gains a `worker_id` / `revision_id` field on each line.
- Coordinator log message records resolved configuration.

**Acceptance:** serial mode produces byte-identical output where
deterministic; numeric outputs identical within ULP tolerance.

### Phase 1 — Concurrent alternatives (BIGGEST WIN, MOVED UP)

This is the single change that closes the wall-clock gap on this
server. It does not require touching `calculate_rates_for_revision()`
or extracting `build_revision_snapshot()`.

Tasks:

1. Refactor `run_alternative_series()` (`src/09_daily_series.R:1118`)
   to collect the six `(variant_name, pp_override)` pairs into a list.
2. Run the list through an `alt_runner()` that spawns one R process
   per alternative via `callr::r()` or
   `future::future(plan = multisession)`.
3. Each alternative writes to its own `output/alternative/<variant>/`
   directory and its own log file.
4. Concurrency capped at `--alt-workers` (default per the table).
5. Failure of one alternative is reported and does not kill the others.

**Acceptance:**
- Each alternative's outputs match serial-mode outputs within tolerance.
- Wall-clock for `--with-alternatives` drops from ~9 h alt phase to
  `ceiling(n_alts / alt_workers) × per_alt_time`.
- One failing alt is isolated and clearly reported.

**Expected impact on this server (192 GB, 4 alt workers):**
~9 h alt phase → ~2.5 h.

### Phase 2 — Cached parse reuse for alternatives

Tasks:

1. In the main build, persist `ch99_<rev>.rds`, `products_<rev>.rds`,
   `ieepa_<rev>.rds`, `s232_<rev>.rds`, `usmca_elig_<rev>.rds` next
   to each `snapshot_<rev>.rds`.
2. In `build_alternative_timeseries()`, read these caches if present;
   otherwise fall back to current re-parse path.
3. Cache invalidation: keyed on the JSON file's modification time and
   sha256, stored in a sidecar metadata file.

**Acceptance:**
- Outputs identical to a fresh re-parse run within tolerance.
- Per-alternative wall-clock drops by ~10 min.

**Expected impact:** ~2.5 h alt phase → ~2 h (composes with Phase 1).

### Phase 3 — Per-revision parallel main build

This is v1's Phase 1, mostly unchanged.

Tasks:

1. Extract `build_revision_snapshot()` from the main build loop
   (`src/00_build_timeseries.R`).
2. Use `parallel_lapply_revisions()` from `src/parallel.R` to run
   it across `--workers` workers.
3. Delta generation runs serially after workers finish.
4. Final bind into `rate_timeseries.rds` runs serially.
5. Failed revisions isolated; default behavior is **fail the build**
   if any revision fails (no partial `rate_timeseries.rds`); allow
   `--allow-partial` for the rare case it's wanted.

**Acceptance:**
- Snapshot count, revision ordering, and `rate_timeseries.rds`
  identical to serial mode within tolerance.
- 4-worker run on this server takes ~20-25 min for the main build
  vs. ~62 min serial.

### Phase 4 — Snapshot-first downstream (independent of parallel)

Same as v1's Phase 2 + Phase 4. Ships independently of parallel mode
because it is a memory-stability win on its own.

Tasks:

1. Daily series prefers `aggregate_snapshots_per_revision()` over
   loading `rate_timeseries.rds`.
2. Weighted ETR maps each policy date to its active revision via
   `valid_from` / `valid_until` and loads only the relevant snapshot.
3. Quality report follows the same pattern.

**Acceptance:**
- All current outputs preserved within tolerance.
- Memory peak in downstream steps drops below the per-revision peak.

### Phase 5 — Pre-USMCA snapshot fast path

Tasks:

1. Refactor `calculate_rates_for_revision()` to be expressible as
   `apply_usmca(calculate_rates_pre_usmca(...))`, with the split
   point at line ~2500.
2. Optionally write `pre_usmca_<rev>.rds` during main build (gated
   by a policy flag, default on for cluster builds).
3. New `build_usmca_alternative()` that reads the pre-USMCA snapshot
   and only re-applies the USMCA pass.
4. Wire the four USMCA alts to use this fast path; the other two
   continue to use the full alt rebuild path.

**Acceptance:**
- USMCA alt outputs identical to full-rebuild USMCA alt outputs
  within tolerance.
- Per-USMCA-alt wall-clock drops from ~85 min to ~15 min.

**Expected impact:** combined with Phases 1-3, the full
`--with-alternatives` build on this server fits in well under 1 h.

### Phase 6 — Per-revision parallelism inside alternatives

Once Phases 1-3 are stable, allow per-revision workers within each
alternative (subject to `revision workers × alt workers ≤ memory cap`).
Default to nested off.

### Phase 7 (deferred) — Inner-loop parallelism

Inside `calculate_rates_for_revision()`. Risky, big audit, only after
the rest of the system is stable and benchmarks justify it.

## Logging and failure handling

- Coordinator log: top-level config, worker resolution, revision
  scheduling, alternative scheduling, summary of successes/failures.
- Per-worker logs: parse summaries, validation messages, error trace
  on failure. Stitched into coordinator log on completion in
  revision/alternative order.
- Default failure behavior: **one failed revision fails the run**
  (no partial `rate_timeseries.rds`). One failed alternative does
  **not** fail the run — alternatives are independent outputs.

## Testing plan

In addition to v1's tests:

### Output equivalence

- Serial vs. `--parallel --workers 2` for a 5-revision subset:
  identical snapshot counts, revision ordering, key numeric summaries.
- Serial vs. `--parallel --alt-workers 2`: alt outputs match.
- Serial vs. `--parallel` with cached parses: outputs match within
  tolerance.

### Pre-USMCA equivalence

- Run a USMCA alt via the full rebuild path and via the pre-USMCA
  fast path; compare daily outputs within tolerance.

### Recovery

- Inject a failure in one revision worker: run aborts with clean error;
  no partial `rate_timeseries.rds`.
- Inject a failure in one alternative: other alternatives complete;
  failure surfaced in coordinator log with non-zero exit-status hint.

### Benchmarks

On this server (192 GB, 4-8 cores allocated):

- Baseline serial.
- Phase 1 only (concurrent alts).
- Phase 1 + 3 (concurrent alts + parallel main build).
- Phase 1 + 3 + 5 (everything).

Capture wall-clock, peak RSS, per-stage runtime.

## Acceptance criteria for shipping

1. Serial mode unchanged by default.
2. Parallel full rebuilds equivalent to serial within tolerance.
3. Concurrent alt mode produces alt outputs equivalent to serial
   within tolerance.
4. Worker-safe logs in place.
5. Memory-aware auto-selection logged at run start.
6. Benchmark on this server shows `--with-alternatives` completing
   in ≤ 4 h with default parallel settings.

## Suggested file-level worklist

- `src/parallel.R` — new helper (Phase 0).
- `src/00_build_timeseries.R` — flags, worker orchestration,
  `build_revision_snapshot()` extraction (Phase 0, 3).
- `src/09_daily_series.R` — `run_alternative_series()` refactor for
  concurrency (Phase 1); `build_alternative_timeseries()` cache
  reuse (Phase 2); pre-USMCA fast-path entry (Phase 5);
  snapshot-first daily aggregation (Phase 4).
- `src/06_calculate_rates.R` — split into pre-USMCA / USMCA pass
  (Phase 5).
- `src/08_weighted_etr.R` — snapshot-based date lookup (Phase 4).
- `src/logging.R` — worker-safe routing (Phase 0).
- `src/install_dependencies.R` — optional deps (Phase 0).
- `scripts/submit_build.sh` — update walltime guidance and document
  parallel flags (each phase).
- `docs/build.md` — operational guidance (each phase).
- `README.md` — short note once parallel is GA.

## Open questions

1. Should `--with-alternatives` run **all six** alts by default, or
   should the default trim to a curated set and let users opt in to
   the rest? (Currently all six are gated only on `rebuild = TRUE`.)
2. Are there alternatives beyond the six listed that we expect to add
   regularly? If so, the registry should move out of
   `run_alternative_series()` into a config file (e.g.,
   `config/alternatives.yaml`) so the alt list is data, not code.
3. Is the combined `rate_timeseries.rds` artifact still required
   for every downstream consumer, or could weighted ETR / quality
   read snapshots directly? (Same as v1's Q3.)
4. For the pre-USMCA snapshot, do we keep both pre- and post-USMCA
   snapshots on disk indefinitely, or treat pre-USMCA as ephemeral
   and delete after alt runs? Disk cost: ~2× the current snapshot
   directory.

## Bottom line

The right sequence on this server is:

1. **Concurrent alternatives first** (Phase 1) — biggest single win,
   mechanical change.
2. **Cached parse reuse** (Phase 2) — small but free.
3. **Per-revision parallel main build** (Phase 3) — the original
   plan's centerpiece.
4. **Snapshot-first downstream** (Phase 4) — ships on its own track.
5. **Pre-USMCA fast path** (Phase 5) — biggest payoff per LOC,
   makes four of six alternatives nearly free.
6. **Nested fanout / inner-loop parallelism** (Phases 6-7) — only
   if benchmarks demand them.

Goal: move `--with-alternatives` on this server from ~10 h
(walltime-bound) to under 1 h with safe defaults, while leaving
the laptop / Windows experience unchanged.
