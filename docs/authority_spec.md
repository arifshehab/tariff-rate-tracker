# AuthoritySpec — a unified authority parameter schema for counterfactual scenarios

**Status:** design proposal (revised) · **Date:** 2026-06-03

> **Resolved design decisions** (see also the review that produced them):
> 1. Supports all four scenario kinds — disable, rate bump/floor, **re-scope to new
>    countries**, and **add new coverage**. The last two require recompute, not panel edits.
> 2. A scenario is a **synthetic future revision**; only intervals at/after its
>    `effective_from` are recomputed (dates before are reused baseline unchanged).
> 3. **Statutory scope only.** ETR adjustment knobs (USMCA utilization, auto rebate,
>    metal-content method, subdivision-r, de-minimis) live in a separate
>    `adjustment_params` dimension. A scenario = `{policy} × {assumptions}`.
> 4. Migration parity is **numeric tolerance**, not byte-identical.
> 5. Scenario files use **Census codes** (validated; fail loud on unknown), with
>    group aliases (`ieepa`, `swiss`, `eu27`) resolved to code sets.
> 6. **Current law is a time path** (it embeds scheduled future changes). Baseline
>    defaults to **current-law**; **current-policy** is a canned scenario that cancels
>    scheduled expiries. A past `base:` keeps changes scheduled as of the pin and
>    suppresses only newly-enacted post-pin revisions.
> 7. IEEPA invalidation stays a per-authority `until`, with an `ieepa` group alias so
>    one operation flips reciprocal + fentanyl together.
> 8. Authored 232 programs that overlap existing coverage resolve **highest-rate-wins**.

## Motivation

Today the Budget Lab tariff pipeline runs three repos:

```
tariff-rate-tracker  →  tariff-etrs  →  tariff-model
(statutory rates)       (ETR engine)     (revenue + macro)
```

This is awkward in two ways: the tracker *also* emits ETR output, so there are
two calculator engines kept in lockstep by hand; and counterfactual scenarios
live downstream in ETRs, where they can only overlay the tracker's *flat*
per-product-country rates — they cannot add new tariff coverage or re-scope an
authority across countries.

The goal is to give **tariff-rate-tracker** first-class counterfactual
simulation, then point **tariff-model** directly at it — dropping the
two-engine overlap. This document specifies the data model that makes that
possible: a single per-authority parameter structure (`AuthoritySpec`) that the
baseline parser *produces* from the HTS JSON and the scenario layer *mutates*,
so that **baseline is literally the empty scenario.**

## Pipeline shape: what "params" means and where AuthoritySpec sits

The word *params* is overloaded in this repo; disambiguate before reading on:

- **parsed params (per-authority data)** — `products`, `ch99_data`, `ieepa_rates`,
  `s232_rates`, `fentanyl_rates`, `usmca`. Produced by the `03/04/05` parsers from
  the HTS JSON. Each authority's object is **a different shape**: `s232_rates` is a
  21-field named list (`05:1033`); `ieepa_rates` is a tibble (`05:214`);
  `fentanyl_rates` is yet another tibble.
- **`policy_params.yaml`** — hand-authored constants (country codes, floor rates,
  232 heading definitions). **Not** parsed from JSON; you edit it directly.

AuthoritySpec normalizes the *parsed per-authority params* (plus the relevant slices
of `policy_params.yaml`) into **one uniform shape**. It does **not** change the
parsing, and it does **not** change the calculator's math — only the calculator's
input interface. The translation runs on **every** build; a scenario is just the
same path with one extra step (apply operations to the specs). That is what
"baseline = empty scenario" means literally.

```
BEFORE
  JSON ──parse(03/04/05)──▶ {ieepa_rates(tibble), s232_rates(list),     ──▶ calculate_rates_for_revision(
        (unchanged regex)    fentanyl_rates(tibble), products, …}            products, ieepa_rates, s232_rates, …)
                                                                              └ each authority = its own block/shape
                                                                         ──▶ RATE PANEL (RATE_SCHEMA, 19 cols)

AFTER (baseline)
  JSON ──parse(03/04/05)──▶ same bespoke structs ──★adapter/normalize──▶ [AuthoritySpec × authorities]
        (UNCHANGED)                                 (NEW)                        │ (no operations)
                                                                                 ▼
                                                    calculate_rates_for_revision(specs, products, countries)
                                                    └ ★NEW signature; reads fields off specs; SAME math/output
                                                                                 ▼  RATE PANEL — identical (parity-gated)

AFTER (scenario)  …specs ──★apply operations──▶ specs′ ──▶ calculate_rates_for_revision(specs′, …) ──▶ counterfactual panel
```

What changes / what does not:

| Layer | Changes? |
|---|---|
| Parsing logic (regex / JSON reading, `03/04/05`) | **No** — untouched |
| `param-obj-1 → AuthoritySpec` adapter | **New** |
| Calculator *input interface* (signature + how it reads inputs) | **Yes** — re-plumbed |
| Calculator *math* and *output* (the RATE_SCHEMA panel) | **No** — preserved, parity-gated |

The brittle prose-parsing in `03/04/05` is a real but **separate** concern; folding a
parser rewrite into this migration would conflate two jobs and inflate parity risk.
The adapter wraps the existing parser output as-is (`step 1` below).

## The core idea: a scenario is a synthetic future revision

The repo's spine is already "on date *D*, the rate panel changes to *X*" — that
is what an HTS revision *is*, and why every downstream artifact (interval
encoding, `delta_*.rds`, daily series, ETRs) is derived from the panel rather
than computed specially.

A presidential announcement effective end of July is functionally **a revision
that USITC has not published yet.** So a scenario is a *hypothetical revision*
layered on the tip of the baseline panel and recomputed forward from its
`effective_from` (dates before are reused baseline, untouched).

**The tip is itself a time path, not a flat rate.** Current law as of any date
already encodes scheduled future changes — but they reach the timeline through
**two different mechanisms today**, which the new engine must unify:

- **Expiries** (s122 sunset, Swiss-framework expiry 2026-03-31) are split into
  sub-intervals *after* the panel is built, by `get_expiry_split_points` /
  `collect_expiry_adjustments` in `09_daily_series.R` (`09:46`).
- **Activation offsets** (`effective_date_offset`) are handled *earlier and
  differently* — `filter_active_ch99` (`06:714`) gates them per revision at calc
  time. The expiry splitter does **not** create a sub-interval at a mid-interval
  Ch99 activation offset.

So the baseline path *is* multi-interval, but it is **not** one unified splitter
today (an overstatement to avoid). A scenario must therefore *compose* with this
scheduled path, and the synthetic-revision timeline must **explicitly collect every
schedule boundary** into one splitter (see implementation requirements below). This
keeps baseline and counterfactual symmetric: all downstream derivations work unchanged.

### Where the scenario injects: the parameter layer (not JSON, not the panel)

The pipeline has three layers:

```
A. HTS JSON archives                                  ← raw (never synthesized)
B. Parsed parameters: products, ch99_data,            ← THE INJECTION SEAM
     ieepa_rates, fentanyl_rates, s232_rates, usmca
     + policy_params.yaml
C. calculate_rates_for_revision(B...) → rate panel → stacking → daily / ETR
```

`calculate_rates_for_revision()` (`src/06_calculate_rates.R:704`) already takes
the Layer-B objects as named arguments. A scenario therefore = **build a
modified Layer-B parameter set and call the same function.** All of Layer C's
logic (metal-share assignment, USMCA scaling, stacking) re-runs on the delta for
free — "the calculator still holds," structurally guaranteed.

We do **not** synthesize fake JSON (Layer A), and we do **not** post-process the
output panel (Layer C) — which is what the current `src/apply_scenarios.R` does,
and exactly why it is limited to column edits and cannot introduce coverage or
set archetype tags correctly.

## The schema

`AuthoritySpec` is one envelope every authority uses. The only genuinely complex
authority is Section 232 (steel, autos, copper… each with its own
products/rate/deals), so we model that as a **list of programs**. Simple
authorities (301, s122, s201) are an authority with exactly one program.

```yaml
section_232:
  stacking:
    class: primary_metal          # default; overridable per program (autos use primary_full)
  usmca_treatment: per_program    # 232 varies by program; others set it here
  active: { from: 2025-03-12, until: null }   # null = open-ended
  programs:
    - id: steel
      product_scope: { chapters: ['72','73'] }
      country_scope: { include: all, exclude: [] }    # country exemptions here
      rate:
        default: 0.50
        overrides: { '4120': 0.25 }                   # UK deal — plain SET (not a floor)
      metal: { type: steel, content: full }           # 232-only block
      active: { from: 2025-03-12 }
    - id: autos_passenger
      product_scope: { prefixes: ['870322','870323', ...] }
      country_scope: { include: all }
      rate:
        default: 0.25
        target_total: { eu27: 0.15, '5880': 0.15 }    # all-in FLOOR: max(value-base,0); JP=5880
      usmca_treatment: eligible                        # statutory eligibility only;
                                                       # content-share scaling → adjustment_params
      stacking: { class: primary_full }                # full customs value, not metal-content split
      metal: { type: none }
      active: { from: 2025-04-03 }
```

The **same envelope** for a "simple" authority — Section 301, with the China
gate now a field instead of a hardcoded `if`:

```yaml
section_301:
  stacking: { class: additive }
  usmca_treatment: none
  active: { from: 2018-07-06, until: null }
  programs:
    - id: s301
      product_scope: { list_file: resources/s301_product_lists.csv }
      country_scope: { include: ['5700'] }    # China; was `if (country == cty_china)`
      rate: { by_product_tier: from_list }    # 7.5% / 25% carried by the list file
```

And IEEPA fentanyl — the country-dependent stacking wrinkle, expressed as data:

```yaml
ieepa_fentanyl:
  stacking:
    class: content_split            # scaled by nonmetal_share on 232 products...
    exceptions: { china: additive } # ...except China, which passes through full
  usmca_treatment: exempt
  active: { from: 2025-02-04, until: 2026-02-24 }   # IEEPA invalidation; flip via the
                                                    # `ieepa` group alias (recip + fentanyl together)
  programs:
    - id: fentanyl
      product_scope: { include: all }
      country_scope: { include: ['5700','1220','2010'] }   # CN/CA/MX; freely extendable
      rate:
        by_country: { '5700': 0.20, '1220': 0.25, '2010': 0.25 }
        product_overrides_file: resources/fentanyl_carveout_products.csv
        # NOT an exclusion list — these are per-product LOWER/higher rates (e.g. potash
        # +10%): the engine does coalesce(carveout_rate, fent_rate, 0) (`06:1195`).
        # Modeling it as exclude_file would zero them and understate the rate.
      # True exemptions (Ch98 9802.00.40/50/60/80) are separate — they zero the rate
      # (`06:1230`) and belong in an exempt_file, not here.
```

### Field reference

Every field maps to something the current engine already does — this is a
*normalization* of existing behavior, not new policy.

| Field | Purpose | Where it lives today |
|---|---|---|
| `stacking.class` | `primary_metal` (232, owns the metal-content fraction — **requires a real `metal.type`**) / `primary_full` (232 owns the **full** customs value, IEEPA excluded — for non-metal 232 like autos/drones; no metal block) / `content_split` (scaled by `nonmetal_share` on 232 products — IEEPA recip, s122, CA-MX fentanyl) / `additive` (full rate always — 301, s201, other, China fentanyl) | the `case_when` branches in `src/stacking.R` |
| `stacking.exceptions` | per-country-group override of the class — captures "China fentanyl is additive while others content-split" **as data, not a branch** | hardcoded `country == cty_china` in the fentanyl branch |
| `country_scope` | `{include: all \| [list], exclude: [list/file]}` — the set membership the engine iterates (`country %in% scope`) | hardcoded for 301/fentanyl; parsed-as-data for 232/IEEPA |
| `product_scope` | `{chapters \| prefixes \| prefixes_file \| list_file, exclude_file}` | `section_232_headings`, resource CSVs |
| `rate` | `{default, by_country, overrides, target_total, by_product_tier}` — **three distinct mechanisms**: `overrides` is a plain SET; `target_total` is an all-in FLOOR `max(value−base,0)` (the deal mechanism, recomputed after MFN/base edits); and the IEEPA surcharge-vs-floor switch is a fourth, country-group case | scattered: `s232_rates`, `section_301_rates`, deal floors (`06:1745`), surcharge/floor switch (`06:934`), ch99 extraction |
| `usmca_treatment` | statutory **eligibility metadata only**: `exempt` / `eligible` / `none`. The utilization *math* (per-product shares; scaling of base + recip + fent + s122; auto/MHD content scaling) is **not** here — it lives in `adjustment_params` | `*_usmca_exception` flags + per-program `usmca_exempt` (eligibility); utilization at `06:2522-2646` |
| `active.{from,until}` | activation window — **what a synthetic revision sets**; `until` also models IEEPA invalidation | `effective_date`, heading gates, `IEEPA_INVALIDATION_DATE` |
| `metal` (232-only) | `{type: steel\|aluminum\|copper\|none, content: full\|share}` → drives `metal_share`/`nonmetal_share` | `deriv_type`, `metal_content`, `s232_annex` |

What disappears into fields: the **heading gate**
(`grepl('9903.94...', ch99_code)`) becomes `active.from`; the **China `if`**
becomes `country_scope`; the **`*_usmca_exception` flags** become
`usmca_treatment`. Each hardcoded thing becomes data.

### Baseline semantics the field list must still absorb

The table above is necessary but **not sufficient** for parity. The live
calculator carries behavior the current draft drops; each must land either as an
explicit field or as an explicit pointer into `adjustment_params`, or baseline
will not reproduce:

- **IEEPA phase precedence** — Phase 1 / Phase 2 / country-EO entries stack across
  phases but not within; within a phase the country entry supersedes the group and
  the highest wins (Brazil 10%+40%=50%, Tunisia max(15%,25%)=25%). `06:856-874`.
- **Country-EO exemptions vs Annex A** — country EOs (Brazil 9903.01.77 …) must
  bypass the universal Annex A or they are wrongly suppressed. `06:801`.
- **Floor-product exemptions** — `floor_exempt_products` zero the reciprocal rate
  for exempt HS8×country-group pairs. `06:997`.
- **Ch98 fentanyl carve-out** — US Note 2(v)(i): the 9802.00.40/50/60/80 set zeros
  `rate_ieepa_fent`. `06:1230`. This is a *true exemption* (→ `exempt_file`).
- **Fentanyl product carve-outs** — `fentanyl_carveout_products.csv` is a per-product
  **rate-override** list (potash/energy at a *lower* rate), `coalesce(carveout_rate,
  fent_rate, 0)` (`06:1195`) — **not** an exclusion. It belongs under `rate`
  (`product_overrides_file`), never `exclude_file`. Two different file roles —
  rate-override vs scope-exclusion — must stay distinct in the schema.
- **Annex overrides** (April 2026) — `annex_1a/1b/2/3` rates with a guard that
  preserves separate heading-program rates (EU cars under 9903.94.51). `06:1982`.
- **Auto rebate / US-content shares**, **subdivision-r blends**, **de-minimis** →
  `adjustment_params` (these are modeling assumptions, not statute).
- **Section 201** — `rate_section_201` is a live authority column the draft ignores.

### Value-configured vs. structure-configured

The distinction that motivates this whole schema: `cty_china = '5700'` being in
config makes the *value* "China" configurable, but the *fact that 301 applies to
exactly `{China}`* is still a hardcoded branch condition — you cannot re-scope
it without editing code. AuthoritySpec promotes every authority from
**value-configured** to **structure-configured**: the set membership itself
(`country %in% spec$country_scope`) is a config list the engine iterates.

Section 232 is already structure-configured for country scope (it parses exempt
lists and country-specific deals from the Ch99 descriptions). 301 and fentanyl
are only value-configured. **The work is promoting them all to the 232 shape.**

### Section 232 program overlap and precedence

A product can match more than one 232 program, so `programs` needs a first-class
resolution rule — the easy "232 on drones" case is easy only because it overlaps
nothing. Baseline behavior to preserve, and the authoring default:

- **Highest rate wins** when a product is in multiple heading programs (`06:1429`,
  `max(heading_232_rate)`). This is also the default for authored/scenario programs.
- **Semi-exclusion** — semiconductor articles are stripped from auto/copper/steel
  lists so only the 25% semi rate applies (Note 39(a); `06:1386`).
- **Blanket chapters over heading lists** — chapter-level steel/aluminum take
  precedence over heading-program membership.
- **Annex-override guard** — the annex catch-all must not wipe a product's separate
  heading-program rate (`06:1982`, `heading_program_products`).
- For an overlapped product, the **winning program** also supplies `metal`,
  USMCA-eligibility, and `stacking.class` — these are not independently mixable.

## The scenario delta: operations on specs

A synthetic future revision is a small list of operations over the baseline
specs — the uniform replacement for today's `disable:` / `patches:`
(`config/scenarios.yaml`).

A scenario has **two independent dimensions**: `policy` (statutory deltas over the
specs) and `assumptions` (modeling deltas over `adjustment_params`). Either may be
empty. `baseline_mode` selects current-law (keep scheduled expiries) vs
current-policy (cancel them); `base` pins the branch point.

```yaml
scenario: drone_232_july2026
description: "232 on drones at 25%, effective 2026-07-31"

policy:
  base: latest                     # or a YYYY-MM-DD pin (see base-pinning below)
  baseline_mode: current_law       # current_law (default) | current_policy
  operations:
    - op: add_program              # the drone case — NEW coverage
      authority: section_232
      effective_from: 2026-07-31
      program:
        id: drones
        product_scope: { prefixes: ['8806'] }
        country_scope: { include: all }
        rate: { default: 0.25 }
        stacking: { class: primary_full }  # 232 owns FULL customs value, IEEPA excluded;
                                           # no metal content (primary_metal would be invalid here)
        usmca_treatment: none

    - op: set_country_scope        # the re-scoping case
      authority: section_301
      program: s301
      country_scope: { include: ['5700','5520'] }   # China + Vietnam (5520)
      effective_from: 2026-07-31

    - op: set_rate                 # the simple rate-bump case
      authority: ieepa_reciprocal
      country: '5520'              # Vietnam
      rate: 0.46
      effective_from: 2026-07-31

assumptions: {}                    # e.g. usmca_utilization, auto_content_share overrides
```

**Operation verbs:** `add_program`, `disable` (authority or program), `set_rate` /
`add_rate` / `target_total`, `set_country_scope`, `set_active`. Each carries
`effective_from`.

**Resolution rules** (must be specified, not implied):
- Operations apply **in listed order**; later ops on the same target win.
- `set_rate` sets `rate.default`; `set_rate` with `country:` sets `rate.overrides[country]`;
  `add_rate` adjusts; `target_total` sets the all-in floor. They do not silently
  cross-write each other.
- `authority` may name a **group alias** (`ieepa` → reciprocal + fentanyl) so one op
  hits both without manual sync.
- Unknown authority/program id, unknown census code, or `primary_metal` without a
  `metal.type` → **hard error**, never a silent no-op.

**The timeline splitter is new work, not a reuse of `collect_patch_split_dates()`**
(`apply_scenarios.R:292`, which only reads `patches[].filter.from_date`). A synthetic
revision must build a modified spec set, recompute coverage, assign a synthetic
revision id, and append the forward interval(s) — which the current
`09_daily_series.R` interval-splitting does **not** do.

## Three borrowings from tariff-etrs

ETRs independently arrived at the same scenario shape (a dated timeline + a
delta off a base), which validates this model. Three things from its design are
worth adopting:

1. **Explicit dated-timeline framing.** An ETRs scenario is an ordered list of
   effective-dated states, so one scenario can express *sequential* changes
   (e.g. "S122 expires July 24, *then* pharma 232 layers on Sept 29"). Our
   `operations[].effective_from` already supports this; adopt the framing — a
   scenario *is* a mini revision-timeline appended to the baseline.

2. **A pinnable base, not just `latest`.** ETRs' `historical: '2026-02-24'`
   lets a counterfactual delta off a *specific* base rather than always the tip.
   Support both `base: latest` and `base: <date>` — useful for reproducibility
   and "what if we'd done X back in April." **Semantics of a past pin:** keep every
   change *already scheduled as of the pin* (the current-law time path continues to
   bend — s122 sunset, Annex III, etc.) and suppress only revisions *enacted after*
   the pin. Deltas layer on top; they do not overwrite scheduled changes unless an
   op explicitly targets one. `baseline_mode: current_policy` is the canned scenario
   that *does* cancel the scheduled expiries (`set_active until: null`), so
   current-law and current-policy share one engine — current-law is the empty
   scenario, current-policy is a standard named one.

3. **The statutory / adjustment-parameter boundary.** ETRs keeps statutory
   rates (the dense CSV from the tracker) separate from *adjustment* parameters
   (metal-content method, `us_metal_origin_share`, `de_minimis_weight_share`,
   USMCA shares) in `other_params.yaml`, overlaid by simple shallow-merge. Keep
   that boundary: AuthoritySpec owns statutory structure; a separate
   `adjustment_params` object owns ETR adjustment knobs. Coarse shallow-merge is
   fine for scalar knobs — reserve the richer operation vocabulary for statutory
   structure.

### Why this is complementary to ETRs, not redundant

ETRs has *already migrated off* structured statutory config onto the tracker's
dense `statutory_rates.csv.gz`; its structured per-authority YAMLs
(`config/archive/*/s232.yaml`, `ieepa_reciprocal.yaml`) are legacy, and are
essentially a subset of `AuthoritySpec`. Because ETRs now holds *flat* rates, its
reforms can only tweak adjustment parameters — it **cannot** add coverage or
re-scope an authority. ETRs' architecture already assumes statutory deltas come
from upstream. `AuthoritySpec` is exactly that missing upstream half.

| | Tracker (`AuthoritySpec`) | ETRs (reform overlays) |
|---|---|---|
| Owns | statutory structure: scope, rates, coverage, stacking | adjustment params: metal content, exemption shares, USMCA |
| "232 on drones" / "301 → Vietnam"? | ✅ structured scope, upstream | ❌ flat rates, downstream |

## Data flow under the new model

```
JSON archives ──parse(03/04/05)──▶ [AuthoritySpec × authorities]  ◀── baseline = specs as-is
                                            │                          scenario = specs + operations
                                            ▼
                  calculate_rates_for_revision(specs, products, countries)
                                            │   (one apply path; stacking.class picks the math)
                                            ▼
                                       rate panel ──▶ stacking ──▶ daily / ETR
```

`calculate_rates_for_revision()` stops taking `ieepa_rates`, `s232_rates`,
`fentanyl_rates` as separate ad-hoc args and takes **one list of
`AuthoritySpec`**. The parsers' job becomes "normalize JSON into specs." The
scenario layer's job becomes "apply operations to specs." Both hand the
calculator the identical shape.

## Implementation requirements surfaced in review

Three things the schema implies but the current code does not yet support:

1. **Per-revision spec persistence (for `base: <date>`).** `policy_params.yaml` is
   *current-only* — it is not versioned as "what we knew on 2026-02-24" (IEEPA
   invalidation date, s122 expiry, Swiss/Annex settings, horizon all live in the
   single current file). A past pin would otherwise leak *today's* future knowledge
   into a historical baseline. Requirement: each baseline revision **saves its
   normalized `AuthoritySpec` + `adjustment_params`**; a pinned `base:` loads the
   saved state at-or-before the pin; a scheduled future event continues only if it
   was already encoded in that saved state. Without this, "past base" is reproducible
   only by `git checkout`, not by scenario config.

2. **A resolved-program intermediate table (before collapsing to `rate_*`).** The
   output panel collapses 232 down to `rate_232` + `metal_share`, which is *not
   enough* for a generic stacker: two rows can both have `rate_232 > 0` yet need
   different stacking (steel owns only the metal-content fraction; autos/drones own
   full customs value; semis/annex have special overlap rules). The stacker cannot
   infer this from `rate_232` alone. Build an intermediate
   `(hts10, country, authority, program_id, rate, stacking_class, metal_type,
   usmca_treatment)` table at resolution time, then collapse to the `rate_*` columns
   *after* stacking. This is what makes the `stacking.class` generalization (step 3)
   actually reliable.

3. **A unified timeline splitter.** The synthetic-revision builder must collect **all**
   schedule boundaries into one splitter — `active.from` / `active.until`, policy
   expiries (s122/Swiss/Annex), Ch99 `effective_date_offset` activations, scenario
   `effective_from`, and the horizon — rather than relying on today's two separate
   mechanisms (`filter_active_ch99` + `get_expiry_split_points`), which do not cover
   mid-interval Ch99 activations.

## Migration plan (incremental, not a rewrite)

Each step is independently shippable and leaves the panel output **within numeric
tolerance** (refactors reorder float ops, so byte-identity is the wrong bar).

0. **Parity harness first.** Extend `scripts/submit_alt_equivalence.sh` (today it
   `cmp`s only the 6 *alternatives*) to also gate the **baseline** panel, and add a
   **tolerance comparator** (per-cell ε + matching aggregate ETR/revenue) plus a
   **per-authority golden** so every later step is checkable. This is the safety net
   the rest of the plan leans on; it does not exist yet.

   The change also has real **API blast radius**: replacing `ieepa_rates` /
   `s232_rates` / `fentanyl_rates` with one spec list touches both build paths
   (`00_build_timeseries.R:253`, `09_daily_series.R`). Add an explicit **adapter**
   step (below) before any generic loop.

1. **Normalize the inputs.** Wrap today's `s232_rates` / `ieepa_rates` / etc.
   into the `AuthoritySpec` shape *without* changing the 17-step calc — the
   steps read fields off the spec instead of the ad-hoc structs. This is also
   where the **vestigial `s232_rates` re-extraction is removed**: today
   `calculate_rates_for_revision()` always re-derives `s232_rates` from the
   date-gated `ch99_data` (`06:721-726` and `06:1276-1278`), discarding the
   passed-in argument. Make the spec authoritative (gate it upstream) so a
   synthetic spec is injectable, and move program activation into the structure
   (`active.from`) instead of the raw-Ch99 grep at `06:1313`.

2. **Un-hardcode scope** for 301 / fentanyl: replace the
   `if (country == cty_china)` branches in `src/stacking.R` with
   `country %in% spec$country_scope`. Small, high-value, unlocks re-scoping
   scenarios.

3. **Generalize stacking** to read `stacking.class` + `stacking.exceptions`
   instead of literal branches — this is where the China-fentanyl special case
   becomes data.

4. **Collapse steps opportunistically.** Once authorities are uniform specs, the
   per-authority step blocks can merge into a generic "apply each spec" loop.
   Optional polish, not a prerequisite.

USMCA is the one authority left as-is: its `{Canada, Mexico}` scope is
definitional, not a policy choice.

### End-state (future, not part of the initial migration)

Once steps 1–4 hold parity and per-revision spec persistence is in place, the
**adapter and the bespoke `param-object-1` structs can be removed entirely**: the
parser emits `AuthoritySpec` directly ("normalize JSON into specs"). This is a *fold*,
not a deletion — the extraction logic moves into the parser rather than disappearing,
so the performance win is modest (the saved cost is the reshape, not the parsing). The
real wins are a single source of truth and removing the redundant re-extraction that
`00_build_timeseries.R:233`, `09_daily_series.R:1156`, and `06` (internally) each do
independently today. Why it is a *later* step, not the first one:

- It must follow parity lock-in — emitting specs directly changes parsing, shape, and
  the calculator interface at once, which is unbisectable if parity breaks.
- All five build/read sites (`00`, `09`, `06`, `generate_etrs_config.R`) must migrate
  together, consolidating the three independent pre-extractions into one.
- The spec is assembled from JSON **plus** `policy_params.yaml`, so "parser emits spec"
  is really "parser + config-merge emits spec"; some `object-1` fields (`has_232`,
  `auto_has_deals`) are gating scratch and need triage, not a 1:1 copy.
- It composes with per-revision persistence: the persisted spec then becomes the
  canonical per-revision artifact, and `param-object-1` has no remaining consumer.

## Open questions

- **Rate representation for product-tiered authorities** (301 at 7.5% / 25%):
  carried by the `list_file` (`by_product_tier`), or split into multiple
  programs? The list-file approach matches the current `s301_product_lists.csv`.
  Note `add_program` for a file-backed authority has no inline tier path today —
  adding *new* 301 product coverage in a scenario needs a file or an inline tier list.
- **Effective dates beyond the horizon**: scenarios effective in 2027 require
  extending `series_horizon` (currently `2026-12-31`).

_Resolved during review:_ `adjustment_params` is a **separate scenario dimension**
(decision 3), not folded into the spec. Identifiers are **Census codes** (decision 5).
Parity is **numeric tolerance** (decision 4). Baseline is **current-law by default**
with current-policy as a canned scenario (decision 6).
