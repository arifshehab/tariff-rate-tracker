# Scheduled future tariff activations ("turn-ON" dates) — code-review findings

**Status:** Investigation only. No code changed. Written 2026-06-04 (John asked for a
deep, code-grounded read of what implementing this actually requires).

**Relationship to the other doc:** `docs/scheduled_activations_plan.md` is the plain-language
plan note (the *what* and *why*). This doc is the code-level companion (the *how*, with exact
seams, file/line references, and the gotchas you only see by reading the code). Where the two
disagree, this one is newer and code-verified — see especially the **timeline-splitter
refinement** in §5, which simplifies the plan note's step 3.

The pharma example is the motivating case: a tariff announced in (say) April, legally effective
in September, that is *certain* to happen but does not yet appear in any HTS archive. Today the
baseline series silently omits it. We want it in the baseline forward projection.

---

## TL;DR

1. **The turn-OFF machinery (expiries) is a useful conceptual mirror but NOT the implementation
   mirror.** Turning a rate *off* is cheap — zero a column on the dates after the sunset
   (`apply_expiry_zeroing`, `helpers.R:498`). Turning a rate *on* is **not** the symmetric
   operation, because the post-activation rate doesn't exist anywhere yet: for new coverage the
   product×country rows aren't even in the sparse panel, and for a bump the future value differs
   from today's. Turning on requires *recomputing* through the calculator. So the right
   implementation is a **synthetic future revision**, not an "activation-zeroing" pass.

2. **Almost all the machinery already exists and is validated.** The calculator already accepts
   scenario operations (`build_revision_snapshot(..., operations=)`, `00:91/124-126`), the ops
   engine already has `add_program` / `set_rate` / `set_country_scope` (`src/scenario_ops.R`), the
   new-coverage seeder already injects a brand-new tariff onto `rate_other`
   (`src/new_coverage.R`), and the assembly step already turns a list of dated snapshots into a
   gapless interval panel purely by ordering on `effective_date` (`00:262-270`). A synthetic
   revision drops into that machinery with **one extra snapshot file + one extra `rev_dates`
   row**.

3. **The genuinely new work is small and well-bounded:** (a) a config block of scheduled
   activations, (b) a thin builder that builds the *tip archive stamped at the future date D with
   the scheduled op applied* (the one missing primitive — `build_revision_snapshot` today
   resolves its archive *by* the revision id, so it can't build "the latest archive as of a future
   date"), (c) inserting those synthetic snapshots + `rev_dates` rows into the baseline assembly,
   and (d) provenance labeling so consumers know a revision is a projection, not an observed HTS
   archive.

4. **The timeline splitter mostly does NOT need to change** (refinement over the plan note's step
   3). A synthetic revision creates its own interval boundary at D *via the revision list*; the
   `09` splitter only handles boundaries that fall *strictly inside* a single revision's interval
   (expiries). See §5.

5. **One real modeling gap to flag — and what it is NOT.** Changing an **existing** 232 (steel,
   aluminum, copper, autos, trucks, wood, semiconductors) is fully solved and stacks correctly.
   The gap is adding a tariff on a **brand-new product category** (pharma = chapter 30): the only
   "add a new tariff" tool books it as a plain **additive** add-on (`rate_other`), which stacks on
   top of everything. A real 232 instead *displaces* the reciprocal on the goods it covers, so the
   additive path double-counts (e.g. pharma 25% on top of a 15% reciprocal = 40%, when it should be
   ~25%). See §6.3 — a decision/scoping point, not a blocker for the mechanism.

---

## 1. The reference mechanism: how turn-OFF (expiry) works today

This is the working, config-driven sunset. It is the *conceptual* template, and §3 explains why
the *implementation* can't be a literal mirror.

**Config** (`config/policy_params.yaml`):
- Section 122 sunset — `section_122.expiry_date: '2026-07-23'` (the last *active* day), plus
  `finalized: false` (set `true` and the expiry is ignored, treated as permanent).
- Swiss framework — `swiss_framework.expiry_date: '2026-03-31'` + `countries: ['4419','4411']`
  (a *country-scoped* turn-OFF on `rate_ieepa_recip`).
- Horizon — `series_horizon.end_date: '2026-12-31'` (how far the forward projection runs).

**The expiry registry** (`src/helpers.R`, `collect_expiry_adjustments()`, ~`395-420`): builds a
list of `{expiry_date, column, [countries], label}` for each non-finalized sunset. This is the
extensible seam for turn-OFFs.

**Interval splitting** (`src/09_daily_series.R`, ~`321-336`): for each revision interval, it
computes `timeline_split_points(valid_from, valid_until, expiry_boundaries(policy_params))` and
splits the interval into sub-intervals at each boundary, e.g. `[2026-02-24, 2026-07-23]` +
`[2026-07-24, 2026-12-31]`.

**Zeroing per sub-interval** (`src/helpers.R`, `apply_expiry_zeroing()`, ~`498-515`): for each
sub-interval start `sub_start`, if `sub_start > expiry_date` it zeros the column (globally, or only
for the scoped countries). This is called from every aggregation fn in `09`.

**Boundary convention** (`src/timeline.R`, ~`37-41`): a boundary is the *first day of the new
state*. A "last live day" expiry `E` maps to `E + 1`; a "first dead day" cutoff `U` maps to `U`.
`boundary_from_expiry()` / `boundary_from_until()` reconcile the two off-by-one conventions onto
one grid.

**The horizon / forward projection** (`src/00_build_timeseries.R`, `assemble_timeseries()`,
`262-270`): every revision runs `valid_from = effective_date` to `valid_until = lead(effective_date)
- 1`; the *last* revision's `valid_until` is set to `horizon_end` (2026-12-31). That is the "carry
the latest revision flat to the horizon" behavior.

---

## 2. How a revision becomes the panel (the insertion substrate)

This is the load-bearing detail for the recommended approach, verified directly.

`assemble_timeseries()` (`src/00_build_timeseries.R:194`):
- **Discovers snapshots by globbing** `^snapshot_.*\.rds$` in the output dir (`00:201`). It does
  **not** consult a manifest — any `snapshot_<id>.rds` on disk is included.
- Binds them all (`rbindlist`, `00:232-242`), enforces the schema (`00:245`), sorts by
  `effective_date` (`00:249`).
- **Derives intervals purely from `rev_dates`** (`00:262-270`): filters `rev_dates` to revisions
  actually present, `arrange(effective_date)`, `valid_from = effective_date`,
  `valid_until = lead(effective_date) - 1`, last one → `horizon_end`. Then left-joins those
  intervals onto the panel by `revision` (`00:272-274`).

**Consequence — inserting a synthetic future revision dated D requires exactly two things:**
1. A `snapshot_<synthetic_id>.rds` file on disk in the output dir (the panel for that revision).
2. A row in `rev_dates`: `{revision: <synthetic_id>, effective_date: D}`.

Then assembly automatically: orders D last (it's the newest), sets the synthetic revision's
interval to `[D, horizon]`, and **shortens the prior tip's `valid_until` to `D - 1`** (because
`lead()` now points at D). No change to the interval logic itself.

**The completeness gate is not in the way:** the `expected_revisions` check (`00:211-227`) only
fails on *missing* expected revisions (`setdiff(expected_revisions, revs_on_disk)`); an *extra*
snapshot on disk is fine. (If we want the gate to know about synthetic revisions, add them to the
expected set; otherwise leave it.)

**The panel schema** (`src/rate_schema.R`, `RATE_SCHEMA`) already carries `revision`,
`effective_date`, `valid_from`, `valid_until` plus the per-authority `rate_*` columns and
`total_*`. A synthetic revision needs no schema change.

**Publish:** the rate panel tariff-model consumes is written under `actual/timeseries/`
(`publish_internal.R`, per the Phase-5 work). A synthetic revision is just more rows in that same
panel — no publish-path change, though see §7 on provenance/metadata.

---

## 3. The key asymmetry: why turn-ON is a synthetic revision, not "activation zeroing"

The plan note calls activations "the mirror image of the expiry mechanism." That's the right
intuition but the implementations are **not** symmetric:

| | Turn-OFF (expiry) | Turn-ON (activation) |
|---|---|---|
| What changes | A rate that **already exists** in the panel | A rate that **does not exist yet** |
| The operation | Zero a stored column on the post-date sub-interval | **Recompute** the rate (new value, possibly new rows) |
| New coverage? | N/A | The panel is **sparse** — pharma rows may not exist at all; must be *seeded* |
| Cost | Cheap, in-place (`apply_expiry_zeroing`) | Full calculator pass (stacking, USMCA, etc.) |

You cannot implement turn-ON as "the inverse of `apply_expiry_zeroing`" because there is no stored
post-activation value to un-zero. The post-activation rate has to be *computed* — which means
running `calculate_rates_for_revision` with the scheduled change applied. That is exactly a
**synthetic revision**. (This is also why John's "synthetic future revision" framing is the
correct one — it's not just a convenient framing, it's forced by the sparse-panel / recompute
reality.)

---

## 4. The recommended implementation (synthetic future revision)

End-to-end, using machinery that already exists where possible.

### 4.1 What a scheduled activation produces

For a scheduled change effective on date D, produce **one synthetic revision**:
- **id**: a clearly-synthetic revision id, e.g. `sched_pharma_2026_09_01` (must NOT collide with
  real `rev_*` ids; see §7 provenance).
- **effective_date**: D.
- **panel**: the *tip archive* (latest real HTS revision) re-run through the calculator **stamped
  at effective_date = D**, with the scheduled operation applied.

Re-running the tip archive *stamped at D* (rather than copying the tip panel) is important and
nearly free: the calculator's internal date gates fire as-of D, so the synthetic revision
*automatically* reflects every other scheduled OFF that has happened by D. Example: pharma effective
2026-09-01, and s122 sunsets 2026-07-23 — the synthetic revision built at D=09-01 correctly has
**no** s122 (the `06` s122 gate `effective_date <= expiry_date` is false at 09-01), with no extra
wiring. The forward composition of multiple scheduled changes falls out of the existing
date-gating.

### 4.2 The one missing primitive: "build the tip archive as of a future date"

`build_revision_snapshot(rev_id, eff_date, ..., operations = NULL)` (`00:84-91`) already does
almost all of this — it builds specs, applies operations (`00:124-126`), runs the calculator, and
saves `snapshot_<rev_id>.rds` (`00:141`). The **only** obstacle: it resolves the HTS archive *by*
`rev_id` (`resolve_json_path(rev_id, ...)`, `00:93`). A synthetic future revision has no archive.

**Minimal change:** decouple "which archive to parse" from "what id/date to stamp." Either:
- add an `archive_rev_id = rev_id` parameter to `build_revision_snapshot` (default preserves
  today's behavior; when set, parse that archive but stamp the output with `rev_id`/`eff_date`); or
- write a thin `build_scheduled_activation_snapshot(synthetic_id, D, op, tip_rev_id)` wrapper that
  reuses the tip's parsed Layer-B inputs and calls the calculator with `operations = list(op)` and
  `eff_date = D`.

Both reuse `apply_operations` + `calculate_rates_for_revision` verbatim. The first is smaller and
keeps one code path.

### 4.3 Wiring into the BASELINE build

In the baseline orchestration, after the real-revision loop builds its snapshots and before
`assemble_timeseries`:
1. Read the scheduled-activations config (§7).
2. For each activation, build `snapshot_<synthetic_id>.rds` via §4.2 (tip archive, stamped at D,
   op applied).
3. Append `{revision: synthetic_id, effective_date: D}` rows to the in-memory `rev_dates`.
4. Call `assemble_timeseries(output_dir, rev_dates_augmented, ...)` — unchanged; it globs the new
   snapshots and computes intervals (§2).

In the **parallel array build**, the synthetic revisions depend on the tip and are cheap, so the
simplest placement is the **gather step** (single node, all archives available), which already runs
`assemble_timeseries`. (They *could* be extra array tasks, but gather is simpler and the cost is
~one revision build each.)

### 4.4 The operation itself

The scheduled change is just an ops-engine operation, already supported:
- **New additive coverage** (a brand-new tariff with no existing authority): `add_program` on the
  `other` authority with `rate = list(flat = X)`, `product_scope`, `country_scope`
  (`scenario_ops.R:288-312`). The new-coverage seeder (`src/new_coverage.R`) adds `X` to
  `rate_other` on in-scope existing pairs and seeds missing pairs via `add_blanket_pairs`.
- **Bump / re-scope an existing authority**: `set_rate` (232 per-program, s122),
  `set_country_scope` (301/201), `set_active` — all already implemented and validated
  (`scenario_ops.R`).

---

## 5. Timeline-splitter refinement (simplifies the plan note's step 3)

The plan note's step 3 says "feed the activation dates to the timeline splitter." **For the
synthetic-revision approach this is largely unnecessary**, and that's a simplification worth
recording.

The `09` splitter (`timeline_split_points`, `src/timeline.R:99-103`) only acts on boundaries that
fall **strictly inside** a single revision's `[valid_from, valid_until]`. A synthetic revision
creates the activation boundary at D **as a revision-list boundary** (§2) — D becomes the start of
its own interval, so there is nothing *interior* to split. Expiries that fall after D land inside
the synthetic revision's `[D, horizon]` interval and are handled by the existing
`expiry_boundaries()` feed, which is already wired and unchanged.

So the splitter is needed only for the genuinely-interior boundaries it already handles
(expiries), **plus** one edge case: a scheduled activation that itself has a *sunset* (a temporary
tariff: on at D, off at E > D). That sunset E would need to be added to
`collect_expiry_adjustments` so the splitter zeros it inside the synthetic revision's interval.
That's a small, additive extension, not core.

`collect_schedule_boundaries()` (`src/timeline.R:57-86`) — the comprehensive collector that
already accepts activation dates via its `extra`/`specs$active.from` params — remains the right
tool **if** we later decide to model activations as interior splits of an existing revision rather
than as their own synthetic revisions. It is validated and ready (`tests/test_timeline.R`), but the
synthetic-revision route doesn't require it. (It *is* still the home for the deferred IEEPA
invalidation Feb-20-vs-24 fix — orthogonal to this work.)

---

## 6. What exists vs what's missing

### 6.1 Already built and validated (reuse, don't rebuild)
- `build_revision_snapshot(..., operations=)` applies ops before the calc (`00:91/124-126`).
- `apply_operations` + verbs `add_program` / `set_rate` / `set_country_scope` / `set_active` /
  `disable` / `set_exempt` (`src/scenario_ops.R`).
- New-coverage seeder onto `rate_other`, dormant in baseline (`src/new_coverage.R`).
- Snapshot-glob + `effective_date`-ordered interval assembly (`00:201`, `00:262-274`).
- Expiry splitter + boundary reconciliation (`src/timeline.R`, `09:321-336`).
- Per-scenario operations through the 09 rebuild path (`build_alternative_timeseries(operations=)`)
  — relevant if scheduled activations are *also* offered as what-if scenarios, not just baseline.

### 6.2 New code required (the actual work)
1. **Config block** in `policy_params.yaml` — a list parallel to `section_122`, e.g.
   `scheduled_activations: [{id, effective_date, operation:{op, authority, program|rate|scope}}]`,
   loaded in `src/policy_params.R` alongside the other blocks.
2. **The "tip archive as of future date" primitive** — the `archive_rev_id` param (or thin
   wrapper) on `build_revision_snapshot` (§4.2). This is the only genuinely missing calculator-side
   piece.
3. **Baseline wiring** — build the synthetic snapshots + append `rev_dates` rows before
   `assemble_timeseries`, in the gather step (§4.3).
4. **Provenance/labeling** — mark synthetic revisions (§7).
5. **Tests** — synthetic revision turns the rate on at exactly D and not before; the prior tip's
   `valid_until` correctly shortens to D-1; baseline-without-activations stays byte-identical;
   interaction with an expiry that falls after D.

### 6.3 The modeling gap to flag (NEW product categories, e.g. pharma)

**First, what is NOT a gap.** The seven existing 232 programs — steel, aluminum, copper, autos,
medium/heavy trucks, wood, semiconductors (`S232_RATE_FIELD`, `scenario_ops.R:44`) — are fully
operable: `set_rate` bumps any of them, `set_exempt` changes country exemptions, `disable` turns
them off, and they stack **correctly**. Verified in `src/stacking.R:141-170`
(`default_stacking_policy`): `rate_232` is class `primary` (full rate, and it *drives* the
content-split), while `rate_ieepa_recip` and `rate_s122` are class `content_split` — when a 232
applies (`rate_232 > 0`) the reciprocal/s122 are scaled down to the **non-232 (non-metal) share**
of the good (`compute_nonmetal_share`, `stacking.R:73-110`). So a 232 *displaces* the reciprocal on
the goods it covers. Changing an existing 232 is solved.

**The gap is adding a tariff on a product category that has NO existing program.** Pharma
(chapter 30) is a brand-new 232 category, not one of the seven. The only "add a tariff that doesn't
exist yet" tool is `add_program`, and it (via the new-coverage seeder, `src/new_coverage.R:97-103`)
writes the rate to **`rate_other`** — class `additive` (`stacking.R:150`), which stacks at full
rate on top of everything, regardless of authority. Even calling `add_program(authority =
'section_232', ...)` does **not** help: the seeder collects *any* program carrying a flat rate and
books it to `rate_other`, so it never reaches the 232 stacking path.

**Why that's wrong for a 232 — concrete numbers.** EU pharma, EU reciprocal ≈ 15%, new pharma 232
= 25%:
- *Real 232 behavior:* pharma goods get 25% and the 15% reciprocal is displaced → total ≈ **25%**.
- *Additive `rate_other` (today's tool):* 25% stacked **on top of** the 15% → total ≈ **40%**.
  Overstated by the reciprocal it should have displaced.

Options, in increasing effort (a decision for John):
- **(a)** Model the new tariff as a simple additive add-on (`rate_other`) — fast, uses today's
  machinery, fine **only** if the new tariff's goods don't already carry a reciprocal/232 duty that
  it should displace. For pharma, which would overlap the reciprocal, this over-counts.
- **(b)** Extend `add_program` + the seeder so a new program can attach to `section_232` (or
  another non-additive authority) and route through the 232 stacking path, displacing the
  reciprocal correctly. This is the "right" representation and matches the Phase-8 new-coverage
  design intent. Extra modeling call it forces: the existing content-split math is built around
  **metal** content (steel/aluminum/copper shares); a non-metal 232 like pharma has no metal share,
  so we'd decide whether the reciprocal goes **fully to zero** on pharma goods (full mutual
  exclusion) or splits some other way.

This gap is **not** a blocker for the mechanism (synthetic revisions work regardless) — it's about
which authority/stacking class the new tariff is modeled under, and it only bites when the new
tariff lands on goods that already carry a duty it should displace.

---

## 7. Cross-cutting concerns

- **Provenance (important).** A synthetic future revision is **not** HTS-backed. Two effects to
  handle: (1) `assemble_timeseries` derives `last_revision` from the newest `effective_date`
  (`00:300-304`) — after inserting a synthetic revision, `last_revision` would point at the
  *synthetic* one, which could mislead consumers who read it as "latest observed HTS revision."
  (2) Downstream consumers (tariff-model) should be able to tell projected rows from observed ones.
  Recommend: a clearly-synthetic `revision` id prefix (e.g. `sched_`) and/or a boolean column /
  metadata field marking synthetic revisions, and decide whether `last_revision` should track the
  last *real* revision.

- **Import weights (fork #2).** New-coverage pairs absent from the 2024 Census weights are
  **zero-weighted and loudly reported, never fabricated** (`08`, Phase-8b). For pharma the HTS
  codes are likely already imported (just not yet tariffed), so weights probably exist — but the
  loud report will catch any pair that doesn't.

- **Baseline vs scenario boundary (John's call).** Which scheduled activations are certain enough
  to bake into the *baseline* (e.g. a signed proclamation with a published legal effective date)
  vs. left as a what-if *scenario*? Suggested rule: baseline only for a published legal effective
  date; everything speculative stays a scenario (which already works via
  `build_alternative_timeseries(operations=)`).

- **Parity gating (dependency).** Adding synthetic future intervals **moves forward numbers**, so
  it must be gated by the daily parity harness (now done — `output/run_parity_gate.sh`, golden at
  `tests/golden/9258c93/`). The gate proves (a) every date *before* the earliest activation is
  byte-identical to the current baseline, and (b) the rate turns on at exactly D. The harness is no
  longer a blocker (it was "in progress" when the plan note was written).

- **Composition with other scheduled changes** is automatic via the calculator's internal
  date-gating when each synthetic revision is stamped at its own D (§4.1) — no special handling for
  "pharma on + s122 off" sequences.

---

## 8. Open questions for John

1. **Stacking class for pharma** (§6.3): is the scheduled pharma tariff modeled as a Section 232
   action (correct stacking, more work) or a simple additive add-on (`rate_other`, fast)? This is
   the main modeling decision.
2. **Baseline vs scenario** (§7): only published-legal-effective-date activations in the baseline,
   rest as scenarios — agree?
3. **Provenance** (§7): is a `sched_`-prefixed revision id + a synthetic flag enough, and should
   `last_revision` track the last *real* HTS revision rather than the newest synthetic one?
4. **Temporary tariffs** (§5): do any scheduled activations also have a known sunset (on at D, off
   at E)? If so we extend `collect_expiry_adjustments` for them.

---

## 9. Concrete change list (when we pick this up)

| # | Change | File(s) | Size |
|---|---|---|---|
| 1 | `scheduled_activations:` config block | `config/policy_params.yaml`, `src/policy_params.R` | small |
| 2 | `archive_rev_id` param (parse tip archive, stamp future id/date) | `src/00_build_timeseries.R` (`build_revision_snapshot`, ~84-141) | small |
| 3 | Build synthetic snapshots + append `rev_dates` rows before assembly | gather step / `src/00_build_timeseries.R` orchestration, `src/parallel.R` | medium |
| 4 | Provenance: synthetic id prefix + flag; reconsider `last_revision` | `00:300-304`, metadata, publish | small |
| 5 | (If §6.3 option b) extend `add_program` to attach a 232 program with stacking class | `src/scenario_ops.R`, `src/new_coverage.R`, resolved-program stacking | medium-large |
| 6 | Tests: turn-on at D, prior tip shortens, baseline byte-identical w/o activations, expiry-after-D | `tests/` | small |
| 7 | Gate with daily parity harness | `output/run_parity_gate.sh` | run-only |

**Validation:** run via Slurm (never the login node). Build baseline with an empty
`scheduled_activations` list → must be **byte-identical** to the current golden. Then add one
activation → confirm only dates ≥ D move, the rate is on exactly at D, and the prior tip interval
ends at D-1.
