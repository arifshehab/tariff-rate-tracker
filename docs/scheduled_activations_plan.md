# Plan note: scheduled future tariff activations ("turn-ON" dates)

**Status:** NOT built. Captured 2026-06-04 at John's request. Needs the daily/ETR
parity harness (in progress) to validate before shipping.

## The problem (in plain terms)

The baseline series handles things that turn **OFF** on a known future date, but not
things that turn **ON**.

- **Turn-OFF works.** Section 122 has a statutory sunset (`expiry_date: 2026-07-23`
  in `config/policy_params.yaml`). The build reads that date and zeros `rate_s122`
  from July 24 forward, all the way to the Dec 31 horizon. Symmetric, config-driven.
- **Turn-ON does NOT work.** A tariff that is announced/scheduled to start on a
  future date (e.g. pharma tariffs announced in April, effective September) does
  **not** appear in the series. New rates only enter when they show up in an
  actual HTS archive, and there is no archive from the future. So the forward
  projection (which just carries the last real revision flat to Dec 31) silently
  omits a known, scheduled, going-to-happen tariff.

**Why this matters:** the series feeds tariff-etrs / tariff-model for forward-looking
revenue and macro analysis. Omitting a scheduled future tariff understates future
tariff levels and revenue. For analysis purposes it NEEDS to be in the baseline, not
just expressible as a hypothetical scenario.

## The fix (John's framing: a synthetic future revision)

When a tariff is **scheduled** to take effect on a future date `D` (announced, with a
known rate/scope), create a **synthetic revision dated `D`** on the tip of the
timeline: take the last real revision's panel, apply the scheduled change, and date
the result `D`. The daily/ETR series then naturally gets a new interval `[D .. horizon]`
carrying the new rate, exactly the way a real revision would.

This is the mirror image of the expiry mechanism: expiries split the tip interval and
zero a column at a date; activations split the tip interval and turn a rate ON at a date.

## What already exists (reuse, don't rebuild)

- **The ops engine** (`src/scenario_ops.R`): `add_program`, `set_rate`, `set_country_scope`
  already mutate an AuthoritySpec. Turning on a scheduled tariff = `add_program`
  (new coverage, e.g. pharma) or `set_rate` (bump an existing authority) — already built
  and validated (Phase 6/8).
- **`effective_from` in the AuthoritySpec design**: an operation carries an effective
  date that is meant to split the tip interval. The design always intended this.
- **The interval splitter** (`src/timeline.R`, `collect_schedule_boundaries`): already
  reconciles expiry/activation boundaries onto one "first day of new state" grid and is
  described as "ready for the model-fix + scenario effective_from dates."
- **`build_alternative_timeseries`** (09) already accepts `operations` and applies them
  (Phase 6e) — the rebuild path that produces a modified series.

## What's missing (the actual work)

1. **A baseline config of scheduled activations** — a list in `policy_params.yaml`
   (parallel to the `section_122` expiry block) of known future turn-ons:
   `{authority/program, rate, product_scope, country_scope, effective_date}`.
2. **Wire it into the BASELINE build**, not just scenarios — at assemble/tip time,
   for each scheduled activation, emit a synthetic revision dated `effective_date`
   (= tip panel + the `add_program`/`set_rate` op applied), inserted into the revision
   list before the daily/ETR step.
3. **Feed the activation dates to the timeline splitter** so the tip interval splits at
   each `D` (currently the live splitter is fed expiry boundaries only).
4. **Mark synthetic revisions** so they're distinguishable from real HTS-backed ones
   (a flag/label), and decide how they publish (visible in the series, tagged as
   "scheduled, not yet in HTS").

## Design questions for John (when we pick this up)

- **Baseline vs scenario boundary:** which scheduled activations are certain enough to
  bake into the baseline (e.g. a signed proclamation with a future effective date) vs
  left as a what-if scenario? Suggest: only ones with a published legal effective date.
- **Provenance:** a synthetic future revision is not HTS-backed — it must be clearly
  labeled so consumers know it's a projection, not an observed schedule entry.

## Dependency

Adding synthetic future intervals MOVES the forward numbers, so it must be gated by the
**daily/ETR parity harness** (currently being finished). That harness proves the rest of
the series is unchanged and that the new rate turns on at exactly the right date.
