# AuthoritySpec — a unified authority parameter schema for counterfactual scenarios

**Status:** design proposal · **Date:** 2026-06-03

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

## The core idea: a scenario is a synthetic future revision

The repo's spine is already "on date *D*, the rate panel changes to *X*" — that
is what an HTS revision *is*, and why every downstream artifact (interval
encoding, `delta_*.rds`, daily series, ETRs) is derived from the panel rather
than computed specially.

A presidential announcement effective end of July is functionally **a revision
that USITC has not published yet.** So a scenario is a *hypothetical revision*
layered on the tip of the baseline panel (the latest revision, carried forward
to `series_horizon`). This keeps baseline and counterfactual symmetric: all
downstream derivations work unchanged.

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
    class: primary_metal          # owns metal content (see "stacking classes")
  usmca_treatment: per_program    # 232 varies by program; others set it here
  active: { from: 2025-03-12, until: null }   # null = open-ended
  programs:
    - id: steel
      product_scope: { chapters: ['72','73'] }
      country_scope: { include: all, exclude: [] }    # country exemptions here
      rate:
        default: 0.50
        by_country: { uk: 0.25 }                      # deals / overrides
      metal: { type: steel, content: full }           # 232-only block
      active: { from: 2025-03-12 }
    - id: autos_passenger
      product_scope: { prefixes: ['870322','870323', ...] }
      country_scope: { include: all }
      rate:
        default: 0.25
        floors: { eu: 0.15, japan: 0.15 }             # target_total: cap all-in at value
      usmca_treatment: content_scaled                 # auto content-share scaling
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
      country_scope: { include: [china] }     # was `if (country == cty_china)`
      rate: { by_product_tier: from_list }    # 7.5% / 25% carried by the list file
```

And IEEPA fentanyl — the country-dependent stacking wrinkle, expressed as data:

```yaml
ieepa_fentanyl:
  stacking:
    class: content_split            # scaled by nonmetal_share on 232 products...
    exceptions: { china: additive } # ...except China, which passes through full
  usmca_treatment: exempt
  active: { from: 2025-02-04, until: 2026-02-24 }   # IEEPA invalidation = the `until`
  programs:
    - id: fentanyl
      product_scope: { include: all, exclude_file: resources/fentanyl_carveout_products.csv }
      country_scope: { include: [china, canada, mexico] }   # freely extendable
      rate: { by_country: { china: 0.20, canada: 0.25, mexico: 0.25 } }
```

### Field reference

Every field maps to something the current engine already does — this is a
*normalization* of existing behavior, not new policy.

| Field | Purpose | Where it lives today |
|---|---|---|
| `stacking.class` | `primary_metal` (232, owns metal value) / `content_split` (scaled by `nonmetal_share` on 232 products — IEEPA recip, s122, CA-MX fentanyl) / `additive` (full rate always — 301, s201, other, China fentanyl) | the `case_when` branches in `src/stacking.R` |
| `stacking.exceptions` | per-country-group override of the class — captures "China fentanyl is additive while others content-split" **as data, not a branch** | hardcoded `country == cty_china` in the fentanyl branch |
| `country_scope` | `{include: all \| [list], exclude: [list/file]}` — the set membership the engine iterates (`country %in% scope`) | hardcoded for 301/fentanyl; parsed-as-data for 232/IEEPA |
| `product_scope` | `{chapters \| prefixes \| prefixes_file \| list_file, exclude_file}` | `section_232_headings`, resource CSVs |
| `rate` | `{default, by_country, floors (target_total), by_product_tier}` | scattered: `s232_rates`, `section_301_rates`, ch99 extraction |
| `usmca_treatment` | `exempt` / `content_scaled` / `none` | the `*_usmca_exception` flags + per-program `usmca_exempt` |
| `active.{from,until}` | activation window — **what a synthetic revision sets**; `until` also models IEEPA invalidation | `effective_date`, heading gates, `IEEPA_INVALIDATION_DATE` |
| `metal` (232-only) | `{type: steel\|aluminum\|copper\|none, content: full\|share}` → drives `metal_share`/`nonmetal_share` | `deriv_type`, `metal_content`, `s232_annex` |

What disappears into fields: the **heading gate**
(`grepl('9903.94...', ch99_code)`) becomes `active.from`; the **China `if`**
becomes `country_scope`; the **`*_usmca_exception` flags** become
`usmca_treatment`. Each hardcoded thing becomes data.

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

## The scenario delta: operations on specs

A synthetic future revision is a small list of operations over the baseline
specs — the uniform replacement for today's `disable:` / `patches:`
(`config/scenarios.yaml`).

```yaml
scenario: drone_232_july2026
description: "232 on drones at 25%, effective 2026-07-31"
base: latest                       # delta off the latest revision's specs
operations:
  - op: add_program                # the drone case — NEW coverage
    authority: section_232
    effective_from: 2026-07-31
    program:
      id: drones
      product_scope: { prefixes: ['8806'] }
      country_scope: { include: all }
      rate: { default: 0.25 }
      stacking: { class: primary_metal }    # full customs value
      metal: { type: none }
      usmca_treatment: none

  - op: set_country_scope          # the re-scoping case
    authority: section_301
    program: s301
    country_scope: { include: [china, vietnam] }
    effective_from: 2026-07-31

  - op: set_rate                   # the simple rate-bump case
    authority: ieepa_reciprocal
    country: vietnam
    rate: 0.46
    effective_from: 2026-07-31
```

Operation verbs: `add_program`, `disable` (authority or program), `set_rate` /
`add_rate` / `floor`, `set_country_scope`, `set_active`. Each carries
`effective_from`, which splits the tip interval into baseline-before /
scenario-after — reusing `collect_patch_split_dates()` in
`src/apply_scenarios.R`.

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
   and "what if we'd done X back in April."

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

## Migration plan (incremental, not a rewrite)

Each step is independently shippable and leaves the panel output **identical** —
provable against the existing output-equivalence check
(`scripts/submit_alt_equivalence.sh`, see commits around `77f...`).

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

## Open questions

- **Rate representation for product-tiered authorities** (301 at 7.5% / 25%):
  carried by the `list_file` (`by_product_tier`), or split into multiple
  programs? The list-file approach matches the current `s301_product_lists.csv`.
- **`adjustment_params` home** in the merged engine: a sibling config object to
  the spec list, overlaid by shallow-merge per the ETRs borrowing.
- **Effective dates beyond the horizon**: scenarios effective in 2027 require
  extending `series_horizon` (currently `2026-12-31`).
