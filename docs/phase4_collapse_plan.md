# Phase 4 — Collapse per-authority blocks into a generic spec loop (PRE-WRITE)

> ## ⚠️ DOUBLE-CHECK EVERYTHING IN THIS DOC — IT MAY BE WRONG
>
> This recipe was written **before Phase 3b/3c landed**, deliberately, as parallel work
> (see the AuthoritySpec migration plan). That means:
> - **Every line number here will have drifted.** Phase 3 edits the same file (`06`/`stacking.R`)
>   this doc inventories. Treat all `file:line` references as *"roughly here, go find it"*, not gospel.
> - **The resolved-program table's real shape is assumed, not known.** Phase 3b defines its actual
>   columns/API. Section ["Dependency contract"](#dependency-contract) lists what this plan *assumes*
>   Phase 3 produced — re-verify each assumption against the real code before writing a single line.
> - **Where this doc and the code disagree, the code wins.** This is a hypothesis to re-test, not a spec.
> - Phase 4 is **"optional polish"** in the master plan. If the collapse turns out uglier than the
>   status quo, it is legitimate to stop. The win is deduplication + scenario-reach, not line count.
>
> If you are an agent executing this: start by re-running the inventory (re-grep the blocks below)
> and reconcile it with reality. Budget that reconciliation as step 0.

---

## ✅ EXECUTION OUTCOME (2026-06-03, branch `phase0-parallel-build`) — STOPPED at step 1 by design

**Scope chosen (John): the SAFE slice only** — collapse the two cleanly-foldable blocks (Section 122 +
Section 201); explicitly LEAVE Section 301 (carries the Phase-2e re-scope capability + its parity gate)
and Section 232 (irreducibly bespoke) alone.

**Verdict after step 0 reconcile: do NOT extract `apply_blanket_authority()` at this scope. No code
change shipped.** Reason, verified against the real post-Phase-3 code:

- The ONLY step 122 & 201 genuinely share — new-pair seeding — is **already factored into
  `add_blanket_pairs()`** (`rate_schema.R:272-304`); both blocks already call it (`06:2451`, `06:2496`).
  The "boilerplate" Phase 4 targeted was removed in an earlier phase.
- The per-block remainder is irreducibly authority-specific:
  - **Rate extraction** differs: `extract_section122_rates` (`has_s122`/`s122_rate`) vs
    `extract_section_201_rates` (`has_s201`/`solar_rate`) — different return shapes.
  - **Activation gate** differs: 122 = date-bounded 150-day expiry w/ `finalized` override
    (`06:2408-2416`); 201 = `has_s201` flag + file-exists WARNING/skip (`06:2466-2470`).
  - **Product scope** differs: 122 = all-products-MINUS-exempt-HTS8; 201 = explicit HTS10 include list.
  - **Existing-row update** differs: 122 = unconditional set-or-zero across ALL countries
    (`06:2434-2440`); 201 = set-on-(product∧country)-match, preserve-otherwise (`06:2483-2489`).
- A unified worker for **n=2** would need `out_of_scope={zero|preserve}` + product-scope-mode +
  per-authority prep → net LONGER + indirection, zero new capability. The AuthoritySpec design says
  collapse **"opportunistically"**; n=2 with divergent semantics is not opportune. Plan's own
  stop-clause invoked.

**REVISIT TRIGGER:** extract `apply_blanket_authority()` at **Phase 8 (new coverage)** — once there are
≥3 blanket authorities AND new ones are being added as data, the worker earns its keep. Design 301's
per-country seeding loop + explicit out-of-scope zeroing INTO it at that point (so the re-scope
capability is a first-class input, not a special case).

### Corrections to this doc's pre-Phase-3 assumptions (verified against code 2026-06-03)
- **Line numbers (refreshed):** `calculate_rates_for_revision` @ `06:736`; 301 @ `2267-2399`;
  122 @ `2401-2458`; 201 @ `2460-2504`; 232 base @ `1330-1701`.
- **301 does NOT call `add_blanket_pairs`** — bespoke per-country `lapply` loop (`06:2367-2393`,
  Phase-2e). Excluded from safe scope to protect the re-scope capability + its parity gate
  (`output/check_rescope.R`, `output/validate_gate3.sh`).
- **232 base** confirmed un-collapsible (no `add_blanket_pairs`, dual chapter+heading scope, 3
  country-override layers). Keep hand-written, as planned.
- **Resolved-program table** (`src/resolved_programs.R`): keyed on ephemeral `.pair` (`seq_len`), NOT
  `(hts10,country)`; `program_id` is **authority-level** (301 = one row, NOT split — a generic loop
  iterates 7 authorities, not sub-programs); collapse reproduces `total_additional`/`total_rate`
  within FP floor but does **NOT** produce `net_*`. **Correction:** the inventory's claim that the
  collapse yields `rate_*` / `net_*` / `total_*` is wrong — `net_*` come from
  `compute_net_authority_contributions()` (`stacking.R`), wide-path only, and are not in `RATE_SCHEMA`.
- **Stacking policy** (`stacking.R:141-175`): all authorities route through
  `compute_stacking_contributions` EXCEPT the `tpc_additive` branch (`stacking.R:205-214,255-268`),
  which bypasses the policy object — latent: a new authority added to `default_stacking_policy()` is
  silently ignored in `tpc_additive` mode (non-production path; flag for whoever touches stacking next).

---

## In plain language (for skimming)

Today the rate calculator (`06_calculate_rates.R`) has ~15 hand-written blocks, one per tariff
authority (301, 232, IEEPA, s122, s201, …). Several of them are **near-identical boilerplate**:
load a rate table, pick which products and countries it applies to, write the rate onto matching
rows, add new rows for product/country pairs that didn't exist yet, log a summary. Phase 4 replaces
that copy-pasted boilerplate with **one loop** that reads each authority's settings from a list and
does the same thing generically. Fewer lines, and — the real prize — adding or re-scoping an
authority becomes a data edit instead of a new code block. Some authorities are genuinely weird
(IEEPA's phase-stacking, 232's metal-content scaling and annex tiers) and **stay hand-written**;
forcing them into the loop would make things worse, not better.

---

## Why Phase 4 depends on Phase 3 (can't be done first)

Phase 4 collapses the per-authority blocks into a loop **over the resolved-program substrate that
Phase 3b builds**. Without that substrate the loop has nothing uniform to iterate. Phase 3 also
generalizes the stacking math (3a already did `default_stacking_policy` / `compute_stacking_contributions`
— see `stacking.R`), which is the half of "generic authority handling" that Phase 4 leans on.
So: Phase 3 makes the *data* uniform; Phase 4 makes the *control flow* uniform. Order is load-bearing.

<a name="dependency-contract"></a>
## Dependency contract — what Phase 4 ASSUMES Phase 3 produced (RE-VERIFY EACH)

Before executing, confirm each of these against the post-Phase-3 code. If one is false, that part of
the recipe is invalid until reconciled.

1. **A resolved-program long table exists** at resolution time, one row per
   `(hts10, country, authority, program_id)` carrying at least: `rate`, `stacking_class`,
   `metal_type`, `nonmetal_share` (per type), `s232_annex`, precedence/order rank.
   *(Plan doc lines ~313–325 list the intended columns — but 3b makes the real call. Get the
   actual column names from `src/resolved_programs.R` once it exists.)*
2. **`apply_stacking_rules()` reads `stacking.class` / `stacking.exceptions`** from a policy object
   rather than the literal `case_when`. (3a started this: `default_stacking_policy(cty_china)` in
   `stacking.R` returns per-authority `{net, class, additive_countries?}`; `compute_stacking_contributions`
   builds `.contrib_<net>` columns. **Confirm 3b finished routing all authorities through it.**)
3. **The collapse-back step exists** — i.e. the long table is reduced back to today's wide
   `rate_*` / `net_*` / `total_*` columns, proven within tolerance. Phase 4 must preserve that
   collapse exactly; it only changes *how the long table gets populated*, not the wide contract.
4. **Persisted schema is unchanged** (the Phase-3 output-contract decision: internal-only). Phase 4
   must not change `RATE_SCHEMA` (`rate_schema.R`). If Phase 3 changed it, stop and re-scope.

---

## Block inventory (current `06_calculate_rates.R`, line numbers ~ as of pre-Phase-3)

> Re-grep these; they will have moved. `calculate_rates_for_revision` was ~`:736` (plan doc says
> `:704` — already drifted, which is exactly why you re-verify).

| Block | ~Lines | Writes | One-liner |
|-------|--------|--------|-----------|
| 1 footnote (`calculate_rates_fast`) | 56–194, called ~791 | rate_232/301/ieepa_fent/other | Vectorized footnote pivot; prereq, not a path |
| 1b IEEPA invalidation | 801–819 | zeroes ieepa/fent | SCOTUS kill-switch, date-gated |
| 2 IEEPA reciprocal | 821–1205 | rate_ieepa_recip | Country-level + universal baseline + floors + exemptions |
| 2b post-IEEPA grid | 1315–1328 | (densify) | `ensure_dense_grid`, post-invalidation |
| 3 IEEPA fentanyl | 1207–1313 | rate_ieepa_fent | Blanket CA/MX/CN + carve-outs + Ch98 exemption |
| 4 232 base | 1330–1701 | rate_232, s232_usmca_eligible | Chapter + heading-level, exemptions, overrides |
| 4b 232 auto rebate | 1705–1746 | rate_232 | Rebate deduction |
| 4c 232 deal rates | 1748–1878 | rate_232 | EU/JP/KR/UK floors & surcharges |
| 5 232 derivatives | 1888–1951 | rate_232, deriv_type | Metal-content scaling |
| 5b copper scaling | 1927–1951 | rate_232 | `copper_share` scaling |
| 5c 232 annex override | 1953–2176 | rate_232, s232_annex | April-2026 annex tiers, surcharges, subdivision (r) |
| 6 Section 301 | 2267–2399 | rate_301 | HTS8 China list, scope from spec |
| 6b Section 122 | 2401–2458 | rate_s122 | All-country blanket, Annex II exempt, date-gated |
| 6b1 Section 201 | 2460–2504 | rate_section_201 | Solar CSPV list, all-except-Canada scope |
| 6b2 MFN grid | 2506–2514 | (densify) | `ensure_dense_grid` MFN-only |
| 6c MFN exemption shares | 2528–2599 | base_rate | FTA/GSP adjustment + floor recompute (6d/6e) |
| 7 USMCA | 2601–2755 | all rate_* | Post-authority modifier, 3 modes |
| 8 stacking | 2758–2759 | total_*, net_* | Final mutual-exclusion sum |
| 9 schema/meta | 2761–2769 | revision, effective_date | `enforce_rate_schema` |

---

## Collapse tiers — what folds into the loop, what stays hand-written

### ✅ Collapse now (the clean wins) — blocks 6, 6b, 6b1
**Section 301, Section 122, Section 201.** All three follow the identical shape:
1. load a rate lookup, 2. resolve product scope (HTS8/HTS10 list), 3. resolve country scope
(spec list / all / all-except), 4. activation gate, 5. update existing rows, 6. add blanket-only
rows (all three already call `add_blanket_pairs()`), 7. log. These are the target of the first loop.

### ⚠️ Collapse with care — block 4 (232 base, chapter + heading)
Same skeleton as 301/122/201 **but** carries heading configs, per-heading rates, multi-source
country exemptions/overrides, and per-product USMCA eligibility tagging. Collapsible **only if** the
authority spec can hold: heading→product resolution, per-heading rate, per-heading USMCA flag. Do
this **second**, after 301/122/201 prove the loop, and keep a fast path if it gets gnarly.

### ⛔ Keep hand-written (forcing these into the loop makes it worse)
- **Block 2 IEEPA reciprocal** — phase-stacking across 9903.02/9903.01, universal baseline, EU/JP/KR/CH
  floor override, multi-level exemptions. Genuinely bespoke.
- **Block 3 IEEPA fentanyl** — country×product carve-outs (min of general vs carve-out), Ch98 exemption.
- **Blocks 5 / 5b / 5c 232 derivatives / copper / annex** — metal-content scaling and annex-tier
  *replacement* logic; these are rate *transforms*, not blanket applications.
- **Block 7 USMCA** — applies *after* all authorities, per-authority reduction, mode-dependent.
- **Block 6c MFN shares** — adjusts `base_rate`, triggers downstream recompute.
- **Blocks 1b / 2b / 6b2 / 8 / 9** — control-flow / densification / aggregation, not authorities.

> The honest read: the loop probably absorbs **3 blocks cleanly, 1 with effort, and leaves ~8 alone.**
> That's still a real win (the 3 clean ones are pure boilerplate today), but don't oversell the
> line-count reduction. The strategic value is that 301/122/201 become **re-scopable by data**,
> which is the consolidation goal.

---

## Target shape (sketch — names illustrative, reconcile with 3b's actual table)

```r
# One spec per collapsible authority (301/122/201 first; 232-base later).
blanket_authority_specs <- list(
  section_301 = list(
    rate_column     = 'rate_301',
    product_scope   = list(type = 'hts8_list', source = 's301_product_lists.csv'),
    country_scope   = scope_301,          # from spec; default CTY_CHINA when specs NULL
    rate_lookup     = s301_rate_lookup,   # tibble(country, blanket_rate) or hts8->rate
    activation      = has_active_301_ch99,
    add_blanket     = TRUE
  ),
  section_122 = list(...),                # Annex II exemption -> exemptions field
  section_201 = list(...)                 # all-except-Canada -> country_scope
)

for (auth in blanket_authority_specs) {
  if (!auth$activation) next
  rates <- apply_blanket_authority(rates, auth, products, countries)   # the one generic worker
}
```

`apply_blanket_authority()` is the extracted common worker: scope filter → existing-row update →
`add_blanket_pairs()` → log. The per-authority *differences* (exemptions, scope) live in the spec,
not the code. Stacking is untouched — Phase 3 already made it read the policy.

---

## Step-by-step recipe (execute in this order; gate after each)

0. **Reconcile.** Re-grep every block above; pull the real resolved-program table columns from
   `src/resolved_programs.R`; confirm the [dependency contract](#dependency-contract). Fix this doc.
1. **Extract `apply_blanket_authority()`** from the *current* Section 301 block verbatim (no behavior
   change yet) — it should reproduce 301 exactly when called with a 301 spec. Gate: byte-identical.
2. **Route 122 through it**, moving 122's specifics into a spec. Gate: byte-identical.
3. **Route 201 through it.** Gate: byte-identical.
4. **(Optional, harder) Route 232-base through it** with heading support in the spec. Gate: tolerance
   (232 touches metal shares downstream — may not be bit-identical; lean on the comparator).
5. **Delete the now-dead per-authority block bodies**; keep the specs as the single source.
6. Update `docs/architecture.md` / `docs/build.md` if they describe the per-authority blocks.

## Validation gate (same bar as every migration phase)
- **Flag-off ≡ golden by construction** for steps 1–3 (pure extraction → byte-identical).
- Per-authority `net_*` unchanged where nothing should move.
- Positive test: 301 → Vietnam still moves only `net_301` on VN rows (the Phase-2e capability must
  survive the refactor — re-run that check).
- Full 41-rev sweep via the Slurm array before deleting any block body (`output/validate_specs_slice.sh`
  pattern, REVS overridable). Inner loop: a 2–3 revision slice first.

## Open questions / risks (resolve during step 0)
- Does 3b's table key on `program_id` in a way that splits 301's single block into multiple rows?
  If so the loop iterates programs, not authorities — adjust.
- `add_blanket_pairs()` signature: confirm it's still the shared helper post-Phase-3 (it's `Reused`
  in the plan's file list).
- 232-base may not survive as byte-identical through the loop — decide up front whether step 4 is
  worth the tolerance risk or should be deferred to a later cleanup.
