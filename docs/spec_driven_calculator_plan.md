# Ship-of-Theseus refactor: a spec-driven calculator (Pass 1)

> Durable in-repo copy of the plan-mode plan (`swirling-moseying-coral`), lightly
> reconciled with decisions pinned at execution time. This is the canonical copy
> on branch `theseus`; the planks below carry a **Status** line, updated as each lands.

## Context

The AuthoritySpec layer is the right abstraction and is already live and always-on,
but it is **hollow**: the `rate` field is a verbatim blob behind a sentinel
(`rate$resolved`), and the calculator unpacks it back into bespoke per-authority
locals and runs a ~3,000-line branching body. Three dimensions are "declared but
not obeyed" — **rate**, **stacking**, **timing**. The goal is to incrementally
relocate policy from hardcoded calculator logic into the spec, one parity-gated
plank at a time, until the calculator is a generic engine that *reads* the spec.

Investigation established: the parser is **not** the problem (0 dropped programs
across 43 revisions; only a bounded ~4% non-ad-valorem leak), and there is **no
rewrite justified** — the debt is localized to one file and one pattern. Full
taxonomy of parameter types in `docs/tariff_parameter_taxonomy.md`.

**This plan is Pass 1 only** (the parity-safe relocations). Pass 2 (correctness
fixes that change numbers and need an oracle) is specified in the appendix for the
future, but is **not** in scope now.

## Design decisions (locked with John)

1. **Scope:** Pass 1 only; Pass 2 documented in detail for later.
2. **Workflow:** one long-lived branch (`theseus`), **no PRs** — we just increment
   commits on this branch. (Cut off `9f9837d` on `feat/counterfactual-pharma-301cs`.)
3. **Parity bar:** numeric tolerance per column class (rates vs shares vs weighted ETR),
   NOT byte-identity — refactors reorder float ops.
4. **IEEPA:** done **late** in Pass 1, after the easy authorities prove the loop.
5. **Rate field:** **compositional layers** — `{default, by_country, overrides,
   by_product_tier, default_unlisted_rate, target_total, rate_type}`. Precedence
   `overrides > by_product_tier > by_country > default_unlisted_rate > default >
   target_total`, **parity-locked to current behavior, not invented** (derived from
   `06_calculate_rates.R`). `default_unlisted` is an accepted alias of
   `default_unlisted_rate`.
6. **Floors:** **named modes** in `rate_type` — `floor_static` (232 deals: compute
   once vs the **original** base) and `floor_post_mfn` (IEEPA-recip / Annex-3:
   recompute vs the **post-MFN** base). Both share the math `pmax(0, value − base)`;
   they differ only in *which* base the caller supplies. Plus `surcharge`, `passthrough`.
7. **rate API — descriptor + helper (decision made at execution).** `resolve_rate()`
   is a **pure reader** returning a descriptor `{value, rate_type, floor_base, matched}`;
   a sibling `apply_rate_semantics(value, rate_type, base)` does the surcharge/floor/
   passthrough math. `floor_base ∈ {original, post_mfn}` tells the calculator which
   base to pass — so floor-timing lives where the base values are.
8. **Mixed statutory×adjustment rates** (semiconductor, auto rebate, subdivision-r):
   **leave the blend as a calculator step**; structure only the clean statutory layers.
   Do not pull shares into the spec in Pass 1.
9. **`resolved_programs.R`:** **delete & rebuild** the intermediate table fresh as part
   of the stacking plank (it has drifted — references an orphan `section_301_cs`).

## Target end-state (the dream — reached at the end of Pass 1)

Parser+config emit a complete spec (rate field real, no blobs); the calculator reads
`scope × rate × semantics × stacking` off the spec with only irreducible conditionals;
counterfactuals mutate any dimension incl. IEEPA via a complete verb vocabulary; output
bit-identical-within-tolerance throughout. (Unified timeline + correctness fixes are Pass 2.)

## Branch & workflow

`theseus`, cut off `9f9837d`. All planks accumulate here; **no PRs, no merge** — John
runs the parity gate live (the worktree lacks the gitignored build data). Compute runs
via `sbatch`, never the login node.

## Pass 1 planks (in order)

**Plank 0 — keystone: real compositional rate schema.** — ✅ **DONE** (verified, this branch).
In `src/authority_spec.R`: the `rate` sub-schema (decision 5/6), `resolve_rate()` (the
precedence reader → descriptor) + `apply_rate_semantics()` (the four `rate_type`
semantics, incl. both floor modes), and `validate_rate()` wired into
`validate_authority_spec()`. No calculator change → parity trivially holds. Key
property: the live adapter still parks the real object in `rate$resolved` and fills
the layer names with **sentinel strings** (`from_raw`/`from_list`/
`from_products_base_rate`); the reader + validator treat those as **hollow/absent**, so
existing specs resolve to nothing here and validate unchanged. Tests:
`tests/test_resolve_rate.R` (63 assertions: precedence, both override forms, both floor
modes, hollow-sentinel tolerance, a partial-match regression guard) + the existing
`test_authority_spec.R` (19) and `test_authority_adapter.R` (20, builds the real spec
set end-to-end) still green. Gate: `sbatch scripts/submit_resolve_rate_tests.sh`.
Notable: `overrides` supports **two element forms** — a named scalar `'4120' = 0.25`
(product→rate, any country, the existing convention) and an entry list
`list(products=, countries=(opt), rate=)` (the rich product×country deal form for 4a).

**Plank 1 — Section 301 (prove the loop).** — ✅ **DONE** (parity GREEN: 47/47 artifacts
within tolerance vs tests/golden/9f9837d, full 43-rev recompute, job 13789634).
Adapter `build_s301_additive_tier()` resolves the additive hts8→rate tier (date-gated via
`filter_active_ch99`, suspended-drop, `max()` supersession) into `section_301`'s
`by_product_tier`; the BUILD reads it back via the spec instead of recomputing inline.
country_scope was already spec-driven. `validate_rate` gained the `flat` key (latent
Plank-0 gap: `add_program` uses it).
  - **Plan reconciliation (the line-refs were stale):** stacking.R is already class-based
    (301 = `additive`; no `country==china` branch left — the only former hardcode is
    `additive_countries=cty_china` on *fentanyl*, already data). So Plank 1's real lift was
    the **rate**, not branch deletion.
  - **Fallbacks RETAINED, not deleted:** `test_tpc_comparison` + `run_tests_daily_series`
    call `calculate_rates_for_revision()` **without specs**, so the inline 301 compute +
    `CTY_CHINA` scope must stay until those callers go away. The literal deletion is
    correctly coupled to **Plank 7 (drop the dual signature)**. The build itself is now
    spec-driven (proven by the gate). cs (content-split) 301 flavor left inline — dormant
    in baseline, parity-safe.
  - Adversarial review confirmed the adapter tier == inline tier bit-for-bit (a–g SAFE).

**Plank 2 — Section 201.** `country_scope = {include: all, exclude: [Canada]}`; delete the
Canada-exempt fallback (`06:~2629`); add 201 to the `disable:` vocab (`policy_params.yaml`).

**Plank 3 — Section 122.** Structured blanket rate; calculator reads it; delete the
re-extraction fallback (`06:~2552`).

**Plank 4 — the bulk (per authority).**
- **4a — Section 232** (multi-program; may sub-divide per program): structure each of the
  7 programs' rate (`default` + country deals as `overrides` + named floor modes) + `metal`
  + `stacking.class`. **Leave** semiconductor/auto-rebate/subdivision-r blends as calc steps
  (decision 8). Delete the UK deal hardcode (`06:~2135`); model Taiwan aircraft as a
  program/scope (`06:~2955`).
- **4b — IEEPA reciprocal + fentanyl (LATE, the big rock):** structure `by_country` +
  `default_unlisted_rate` (universal baseline) + `rate_type` (surcharge/floor_post_mfn/
  passthrough) + floor-exempt set. Relocate CA/MX exemption (`06:~1090`), floor-country
  groups (`06:~1020`), phase supersession (`06:~973-1008`) into data; wire the already-
  declared China-fentanyl `stacking.exceptions` so `stacking.R:~145` stops branching.
  IEEPA invalidation stays `active.until` (already wired).

**Plank 5 — stacking generalization.** Delete the drifted dormant `resolved_programs.R`;
rebuild the resolved-program intermediate table fresh; generalize `stacking.R` to read
`stacking.class`/`exceptions` instead of literal branches; dedup the metal-chapter→type map
(currently copy-pasted at `06:~2159`, `~2137`, `09:~555`, `stacking.R:~83`) into one config table.

**Plank 6 — IEEPA scenario verbs.** Now that IEEPA rate is structured, add `set_rate`
(per-country) / `set_country_scope` / `disable` for IEEPA to `src/scenario_ops.R` (today they
error). Baseline = empty ops → parity; add scenario-correctness unit tests.

**Plank 7 — drop the dual signature (end of Pass 1).** Once every authority is spec-driven,
remove the bespoke args from `calculate_rates_for_revision()` so it takes **specs only**.
(Optional within Pass 1; can defer if risky.)

## Verification

- **Baseline golden:** `tests/golden/9f9837d` (the native-format twin of the published
  `2026-06-04_2` vintage; same commit, `policy_params_md5` matches the manifest). Captured
  via `scripts/capture_parity_golden.R`.
- **Per plank:** numeric-tolerance parity gate (panel + daily) via the existing harness,
  ε per column class (decision 3).

  **USE THE PARALLEL ARRAY BUILD — never the serial `00_build_timeseries.R --full`.**
  The monolithic builder's `--workers` flag is a no-op (serial: ~1h45m for 43 revisions;
  Plank 1 burned that once). The array path builds one Slurm task per revision concurrently
  (~10–15 min) and is what built the golden:
    1. `bash scripts/submit_build_array.sh` (with `GATHER_ARGS="--unweighted"` to skip the
       un-gated weighted ETR) — generates the revlist, submits one array task per revision,
       and chains the gather (assemble → daily) via an `afterok` dependency.
    2. then `Rscript scripts/run_parity_check.R --golden tests/golden/9f9837d --artifacts
       snapshot,daily_overall,daily_by_authority,daily_by_country,daily_by_category`.
  - The array path rebuilds **every** revision fresh, so it has no "incremental no-op" trap.
    (The serial builder WITHOUT `--full` silently reuses on-disk snapshots → a false-green
    gate; Plank 1's first run hit exactly this. If ever using the serial path, `--full` AND
    pre-delete `data/timeseries/snapshot_*.rds`.)
  - **Skip the monolithic `timeseries` artifact** in the parity check: the 1.38 GB
    `rate_timeseries.rds` ×2 OOMs at 192 G. The 43 per-snapshot comparisons cover the same
    data one file at a time (memory-safe), with no loss of coverage.
  - The golden is frozen in `tests/golden/`, so the array build overwriting
    `data/timeseries/` is safe.
- **Plank 0:** unit tests on `resolve_rate`/`apply_rate_semantics`/`validate_rate` (no recompute).
- **Planks 1/6:** also add scenario unit tests (rescope 301; rescope/rebump IEEPA).
- A plank is "done" only when parity is green within tolerance AND its bespoke branch(es)
  are deleted (deleting only the branch while leaving scope hardcoded is a silent miss).

  > **Parity ≠ correctness.** The gate compares candidate vs golden, so it only catches
  > *changes* — it is **blind to bugs already baked into the golden** (candidate and golden
  > agree → green). Absolute-invariant unit tests (e.g. `tests/test_rate_calculation.R`) are
  > what catch latent baseline bugs; keep running them alongside the gate. (This is the same
  > reason Pass 2 — behaviour changes — needs an external oracle, not parity.) Live example:
  > the Russia §232 aluminium-surcharge leak (below) is present in the golden, so parity is
  > green on those snapshots while `test_rate_calculation` fails its Russia invariants.

## Hygiene (fold in opportunistically)

- Fix the list-column bug in `scripts/diagnose_parse_loss.R` (the bogus ~70% all-dangling
  metric; `n_dangling_codes=0` is the real signal) before anyone reruns it.

## Known pre-existing bugs (NOT introduced by this refactor; flagged for John)

- **Russia §232 aluminium-surcharge leak.** `tests/test_rate_calculation.R` fails 3 absolute
  invariants (lines ~856/872/908) on `snapshot_2026_rev_5.rds`: the 200% Russia surcharge
  (scoped to *aluminium*) appears to leak onto (a) Russia *steel* (HS 72/73) and (b) Annex-II
  non-semiconductor products that should be §232-exempt (Note 39a invariant). Present in the
  current **golden** data, so the parity gate is green on it — only the invariant tests catch
  it. Behaviour-changing to fix → its own task (likely a Pass-2 / surcharge-scoping item),
  out of scope for the Pass-1 planks.
- Non-fatal quality-report `$`-on-atomic error during the build (build still exits 0); not
  from the spec work (`quality_report.R` doesn't touch `by_product_tier`).

## Appendix — Pass 2 (NOT in scope; specified for the future)

Pass 2 = the **behavior-changing** fixes. They change numbers on purpose, so parity
cannot validate them — each needs an **external oracle**, which does not exist today.

- **P2-0 — build the oracle (gates all of P2).** Restore the TPC benchmark
  (`data/tpc/tariff_by_flow_day.csv`, possibly recoverable from ji252's tree) or curate a
  hand-checked ground-truth set for the worst complex/edge cases. Specify ε per column class.
- **P2-1 — unified timeline splitter.** Feed `collect_schedule_boundaries()` the comprehensive
  set (built + validated in `src/timeline.R`, currently fed only legacy expiries at `09:~326`);
  wire the matching **state-change** at each new boundary (Ch99 offsets → closes the "pharma
  never turns on" hole; IEEPA invalidation mid-interval; annex sunset). Resolve the open
  modeling question (invalidation `02-20` vs `02-24`). Oracle-gated; ~days per edge-type.
- **P2-2 — parser non-ad-valorem (~4% of import value).** Represent compound/specific duties
  the parser currently drops to `NA`/`has_complex_rate`. Oracle-gated.
- **P2-3 — unify scenario surfaces.** Statutory deltas (`operations`) and adjustment deltas
  (`pp_override` / rebuild-alts) are two separate code paths; unify to `policy × adjustment`.
- **P2-4 — per-revision spec persistence.** Save each revision's resolved spec +
  adjustment_params so a `base: <date>` pin reproduces "what we knew then".
- **P2-5 — fold parser→spec, delete Layer B.** Parser emits specs directly. Low value, large
  blast radius; do last.

## Supersedes

This plan consolidates and supersedes the scattered phase docs (`parallel_full_pipeline_plan*`,
`phase4/5/6_*`, `scheduled_activations_plan`) for the calculator-refactor strand.

## Progress log

- **2026-06-05 — Plank 1 landed (parity GREEN).** Section 301 additive rate relocated to
  the spec's `by_product_tier` (adapter `build_s301_additive_tier`); build reads it back.
  Gate (`scripts/submit_plank1_build_gate.sh`): `--full --core-only` rebuild of all 43
  revisions, then `run_parity_check.R --golden tests/golden/9f9837d` → 47/47 artifacts
  within tolerance (job 13789634). Two gate-process bugs caught + fixed before the real
  run: (a) `--core-only` without `--full` is a no-op rebuild (reuses stale snapshots —
  must `--full` and pre-delete snapshots so a rebuild miss can't false-green); (b) the
  monolithic `rate_timeseries.rds` parity load OOMs at 192G — compare the 43 per-snapshot
  files instead (same data, memory-safe). Fallbacks retained (Plank 7 deletes them).
  Pre-existing/orthogonal: 3 `test_rate_calculation` Russia §232 Annex-II invariant
  failures (untouched code path), and a non-fatal quality-report `$`-on-atomic error.
- **2026-06-04 — Plank 0 landed (verified).** Compositional rate schema +
  `resolve_rate`/`apply_rate_semantics`/`validate_rate` in `src/authority_spec.R`; tests
  green via `sbatch scripts/submit_resolve_rate_tests.sh` (63 + 19 + 20 assertions). Two
  bugs caught by the gate before commit: (a) `overrides` must accept the named-map form the
  existing spec test uses, not only the rich entry form; (b) R `$`/`[[` partial-matching made
  `rate$default` silently grab `default_unlisted_rate` — fixed with an exact-name accessor.
