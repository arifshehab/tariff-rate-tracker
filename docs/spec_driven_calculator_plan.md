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

**Plank 2 — Section 201.** — ✅ **DONE** (parity trivially GREEN — see reconciliation; no
rebuild). `section_201`'s `country_scope = {include: all, exclude: Canada}` is in the adapter
and the calculator reads it (`06:` "Plank 2" hook → `resolve_country_scope`); 201 is registered
`SCOPE_DRIVEN` in `scenario_ops.R`, so `set_country_scope`/`set_active`/`disable` all drive it.
Scenario unit tests added for 201 rescope + disable (`tests/test_scenario_ops.R`, mirroring 301).
Gate: `sbatch scripts/submit_plank2_tests.sh` (scenario_ops + spec + adapter; pure-logic, no build data).
  - **Plan reconciliation (the substance pre-landed under "Phase 2e"):** the 301cs branch already
    relocated the 201 scope into the spec + wired the calc read, and that code is **present at
    `9f9837d`** — i.e. in the golden. `resolve_country_scope({all, exclude: Canada})` is
    `setdiff(countries, Canada)` **bit-for-bit**, so the candidate == golden with no number change;
    a 43-rev rebuild would be a guaranteed no-op (skipped to preserve cluster time). Plank 2's real
    remaining lift was the **scenario-test coverage gap** (the test baseline carried a 201 spec but
    never asserted a 201 op) + this reconciliation.
  - **Fallback RETAINED, not deleted** (same as Plank 1): `test_tpc_comparison` + `run_tests_daily_series`
    call `calculate_rates_for_revision()` **without specs**, hitting the `else setdiff(countries, Canada)`
    path. The literal deletion is coupled to **Plank 7 (drop the dual signature)**; the `06:` hook now
    says so.
  - **"`disable:` vocab in `policy_params.yaml`" reconciled:** there is **no** `disable:` key in the yaml.
    The disable vocab lives in `scenario_ops.R::SCOPE_DRIVEN_AUTHORITIES` (already includes
    `section_201`) + `op_disable`. The plan line anticipated a yaml location the live code doesn't use.

**Plank 3 — Section 122.** — ✅ **DONE** (parity GREEN: 47/47 artifacts within tolerance vs
tests/golden/9f9837d — full 43-rev recompute, parity job 13797778 + snapshot-only 13798477).
De-blobbed: the s122 blanket rate moved from the opaque `rate$resolved` blob `{s122_rate,
has_s122}` into the structured compositional `rate$default` layer (`rate_type='surcharge'`).
The calc READS it via `resolve_rate(...)$value` and gates on `value > 0` — bit-exact with the
old `has_s122 ≡ rate>0`. scenario_ops gained a `DEFAULT_RATE_AUTHORITIES` category (`set_rate`
→ `rate$default`, `disable` → 0); section_232 stays the resolved-blob `RATE_DRIVEN` path until
Plank 4a. Dropped the dead `s122_rates_from_specs` accessor. Gates: `sbatch
scripts/submit_plank3_units.sh` (47+19+21 assertions) + `scripts/submit_plank3_parity.sh`.
  - **Not a close-out (unlike Plank 2):** s122's rate was already spec-driven but as a BLOB, not
    a structured layer. Per John — *no half-measures; the premise is to de-blob fully* — this did
    the real structural migration. This is the **template for the remaining blob authorities**
    (s232 = 4a, IEEPA = 4b): blob → structured layer; calc reads via `resolve_rate`; scenario_ops
    mutates the structured field; parity rebuild confirms bit-exact.
  - **Fallback RETAINED** (Plank 1/2 precedent): the specs-less `else extract_section122_rates`
    serves the dual-signature callers (test_tpc_comparison, run_tests_daily_series); deletion is
    coupled to **Plank 7**. The `06:` hook says so. No `--no-config-check` needed (policy_params.yaml
    untouched → hashes to the golden manifest).

**Plank 4 — the bulk (per authority).**
- **4a — Section 232** (multi-program): structure each of the **7** programs' rate
  (`default` + country deals as `overrides` + named floor modes). **Leave**
  semiconductor/auto-rebate/subdivision-r/derivative blends as calc steps (decision 8).
  Delete the UK deal hardcode (`06:2134-2145`); model Taiwan aircraft as a scope (`06:2964-2995`).
  - **Read-path = FULL REPOINT (decided with John, 2026-06-05).** The calc reads §232 via
    `resolve_rate()` directly at all ~36 read sites — NO reassembled `s232_rates` shim. Matches
    the s122 "calc reads the spec" contract literally (John's "no half-measures" call); accepts
    the larger diff + higher parity risk over the low-risk shim.
  - **KEY: the s122 `value>0` gate does NOT transfer.** `has_232` is a **12-term OR-gate**
    (`.s232_recompute_has_232`, scenario_ops.R:69-75) — ORs `auto_has_deals` (TRUE even at
    `auto_rate=0`) + both derivative rates + `wood_rate||wood_furniture_rate`. NOT reducible to
    "any program rate > 0"; keep the explicit gate.
  - **7 spec programs** (`authority_adapter.R:127-141`): steel/aluminum/copper (metal) +
    autos/mhd/wood/semiconductors (full). `pharmaceuticals` = dormant 8th `set_rate` name
    (S1b adds a dormant program for it). `wood` = one program, two rate fields.
  - **Staging = 4 commits, finer S1 (decided with John).** Full-repoint dropped the
    trivial-bit-exact S1 (scalars are entangled with the shared `has_232` gate), so S1 was split
    to isolate the gate risk. Each = commit + full parallel-array parity gate vs `9f9837d`:
    - **S1a ✅ DONE — parity GREEN 47/47** (commit `2a2232e`). blanket steel/aluminum/auto BASE reads
      (`06:1600-1602`) → `rate$default`. Helper `s232_spec_rate(specs, s232_rates, program_id, blob_field)`
      reads `resolve_rate(prog$rate)$value`, falls back to the blob scalar for the specs-less callers (Plank 7).
    - **S1b ✅ DONE — parity GREEN 47/47** (commit `307401b`). heading programs (copper/mhd/wood/semi) +
      a dormant `pharmaceuticals` program get `rate$default`; `compute_heading_gates`/`resolve_heading_rate`/
      `.s232_recompute_has_232` repointed to read program rates off the spec (heading→program-id via the new
      `HEADING_RESOLVED_PROGRAM` map). The non-rate gate inputs (`auto_has_deals`/`auto_has_parts`,
      `wood_furniture_rate`, derivatives) stay on the residual blob. Unit: adapter 31/31, scenario_ops 48/48.
    - **S2 ⬜ NEXT (DESIGN LOCKED 2026-06-05 — see the locked subsection below)** — country deals/overrides/
      exempts de-blobbed. 4 separately-gated sub-commits. **Blanket (exempt + metal HTS overrides + config
      exemptions) → ONE merged `by_country`** (NOT `overrides` — corrects the stale "→ `overrides`/`by_country`"
      framing: a per-country read is `resolve_rate(product=NULL)`, which SKIPS both override forms, so HTS
      overrides parked in `overrides` would silently never be read). **Deals split by CONCEPT** (John's call):
      `overrides` (flat product×country, scope-label form) + a NEW `floors` field; the calc expands the scope
      label to HTS at run time and keeps the floor/surcharge math (decision 8). floors = `floor_static` vs the
      ORIGINAL base; EU27 unversioned. HIGH risk concentrated in the deals slice.
    - **S3 ⬜** — delete UK annex deal, model Taiwan aircraft as a scoped 0, drain the residual blob. MED.
  - **Gate-tooling fix landed (commit `134759f`, src/parity.R):** the `--unweighted` build drops the
    un-gated weighted/ETR columns (`weighted_etr*`, `etr_*`, `*_imports_b`) the golden carries; the
    comparator now skips golden-only columns matching `^weighted_etr|^etr_|_imports_b$` instead of
    false-flagging them. Without this, every 4a daily gate false-fails post-gather-refactor.
  - **DEFER to Plank 5:** metal/stacking shells + the 4-copy metal-chapter→type map (`stacking.R:83`,
    `06:555/2061/2159` — copies already disagree on copper). 4a leaves them.

#### Plank 4a — execution notes & handoff (as of S1b green, 2026-06-05)

> Written for a fresh instance picking up at **S2**. Read this + the Progress log before touching code.

**Architecture as actually built (the full-repoint pattern — reuse it for S2/S3):**
- **`s232_spec_rate(specs, s232_rates, program_id, blob_field)`** (`06_calculate_rates.R`, just after
  `resolve_heading_rate`) is the central read helper. Spec present → `resolve_rate(program$rate)$value`
  (the de-blobbed `rate$default`, incl. 0 — NA only when truly absent → then blob fallback). Specs-less
  dual-signature callers (`test_tpc_comparison`, `run_tests_daily_series`) → the blob scalar. **Retain the
  blob fallback until Plank 7.** Every new S2 read should go through this same spec-first/blob-fallback shape.
- **The residual blob shrinks per stage** and rides on `programs[[1]]` (steel) `$rate$resolved`, read by
  `s232_rates_from_specs(specs)`. After S1a+S1b it still holds: exempt lists, `*_country_overrides`,
  `auto_deal_rates`/`wood_deal_rates`, derivatives, `auto_has_deals`/`auto_has_parts`, `wood_furniture_rate`,
  `has_232`. **S2 drains the deals/overrides/exempts; S3 drains the rest (derivatives stay per decision 8).**
- **`has_232` stays a residual field**, recomputed by `.s232_recompute_has_232(spec)` which reads the 8
  program `rate$default`s off the spec + the residual non-rate terms. **Keep the THREE has_232 formulas in
  lockstep:** `extract_section232_rates` (parser baseline), `compute_heading_gates` (calc), and
  `.s232_recompute_has_232` (scenario_ops). The s122 `value>0` substitution does NOT apply here.
- **scenario_ops:** §232 `set_rate`/`disable` mutate each program's `rate$default` (via `.find_program_index`)
  and recompute `has_232` from the spec; `set_exempt` still writes the residual exempt lists (S2 moves it).
  The scenario behavior is validated by `tests/test_scenario_ops.R` (unit), **NOT** by the parity gate.

**Gate mechanics — learned the hard way (do not relearn):**
- **The build sources LIVE `src/*.R` at task runtime.** NEVER edit live source while a parity build for
  another stage is in flight — late/retried array tasks will compile the half-edited file and silently
  poison the gate. **Workflow that works:** develop the next stage in a git worktree (`git worktree add -b
  <stage>-dev ../trt-<stage> HEAD`), unit-test there (pure-logic tests need no build data), and
  `git cherry-pick` onto `theseus` only once the prior stage's build has finished. (`trt-s1b` on branch
  `s1b-dev` exists and can be reused.)
- **Parity is baseline-only** (empty ops): it validates that the read-repoint is bit-exact, NOT the scenario
  mutations. Each stage is bit-exact *by construction* — `rate$default` holds the same scalar the old blob
  read returned, and `resolve_rate` returns it verbatim. If a stage's gate is RED, a real number moved.
- **Run R via** `module load R/4.4.2-gfbf-2024a` (Rscript isn't on the bare PATH). Pure-logic unit tests run
  fine in the interactive alloc; heavy builds go through Slurm.
- **Gate commands (the live 2-step, ~18 min):**
  1. `GATHER_ARGS="--unweighted" bash scripts/submit_build_array.sh` → array (one task/rev) + `afterok` gather.
  2. once gather done: `GOLDEN=tests/golden/9f9837d sbatch scripts/submit_plank3_parity.sh` (generic; reusable
     for every stage). Verdict in `output/parity_results_<ts>/` + the summary slurm log (`47 passed / 0 failed`
     = GREEN). No `--no-config-check` needed unless a stage edits `config/policy_params.yaml`.

**S2 LOCKED DESIGN (2026-06-05).** Settled via a fan-out workflow (5 mappers → architecture decision →
per-slice adversarial parity verdicts) + two decisions from John. The adversarial pass verified the 3 blanket
slices parity-safe (high confidence) and caught two real blockers in the deals slice (below). **4 separately-
gated sub-commits, cheapest→riskiest:**

1. **HTS metal overrides** (`steel_country_overrides`/`aluminum_country_overrides`, calc `06:1665-1678`) →
   `by_country` on the steel/aluminum programs. Cleanest: parser already census-keys + EU-expands + `max()`-
   collapses these (`05:625-661`), so the adapter copies them straight in. Do FIRST to prove the
   `by_country`-over-`default` plumbing.
2. **Exempt lists** (`steel_exempt`/`aluminum_exempt`, calc `06:1657-1662`) → `by_country = 0` entries, MERGED
   OVER slice 1 (exempt runs *before* the override loop, so the override must win → in a flat `by_country` map
   that means write exempt-zeros first, then overrides). Adapter must **census-expand each ISO/EU token via the
   same three paths `is_232_exempt` uses** (identity-census, `ISO_TO_CENSUS[iso]`, `EU→EU27_CODES`), because the
   blob keys are ISO/EU-tokens, not census. **Baseline is parity-trivial here** (the `*_exempt` lists are EMPTY
   in the golden — steel/alum resolve via the increase branches), so the risk is the WRITE path, not the read.
   **Leave `auto_exempt` on the blob** — `auto_rate` never sets `rate_232` (autos flow through the heading path),
   so `auto_exempt`'s only effect is `s232_country_codes` membership, swamped by the heading-present union; zero
   parity benefit, real edge-case risk.
3. **Config exemptions** (`S232_COUNTRY_EXEMPTIONS`, calc `06:1685-1700`) → `by_country` on steel/aluminum,
   MERGED OVER slices 1+2 (config runs last → wins). Source is `pp$S232_COUNTRY_EXEMPTIONS` (config, already
   census + EU27-expanded). The adapter is per-revision, so it **pre-resolves the date gate** `is.null(expiry) ||
   rev_date < expiry` (**strict `<`**) and bakes only the active entries. The Russia entry (rate=2.0, expiry NULL,
   permanent) flows through here — it is the last config entry, NOT a separate field, and is IN scope. (Distinct
   from the annex-era Russia surcharge at `06:2207-2264`, which reads `annex_cfg`/config, NOT the blob → OUT of S2.)
4. **Auto + wood deals** (calc `06:1882-1989`) — **THE RISKY SLICE.** Split by CONCEPT (John's call), each as a
   structured field the CALC reads (NOT `resolve_rate`), carrying a product **scope label** the calc expands at
   run time (so products stay calc-time → no new parity surface):
   - **flat product×country overrides** (the surcharge deals: UK vehicles 7.5%, UK wood 10%) → `overrides`
     entries in **scope form** `{scope, countries, rate}` (e.g. `scope = 'vehicles'`). These have NO `products`
     key, so `resolve_rate` auto-skips them (`hit_p` requires products → always FALSE) → reader-invisible by
     construction; the calc reads them by scope.
   - **floors** (EU/JP/KR vehicle 15%, UK parts 10%, EU/JP/KR wood 15%) → a NEW `floors` field, entries
     `{scope, countries, floor}`; the calc applies `pmax(floor − base, 0)` against the ORIGINAL pre-232 MFN base
     (`floor_static` / `floor_base='original'` — the #1 parity risk; do NOT "fix" to post-MFN, Pass-2 concern).
   - The adapter **census-expands each deal's ISO/EU country at build time** (mirroring `iso_to_census_vec`:
     `EU → names(pp$eu27_codes)` = 27 codes unversioned; ISO → `ISO_TO_CENSUS`), and tags each entry with the
     deal's `program` as the scope label. Surcharge entries flat-REPLACE `rate_232`; floors `pmax`. No
     product×country cell is double-hit (vehicles/parts disjoint; wood once-per-country), so order is preserved
     but non-observable.

**THE ONLY Plank-0 touch in S2 — additive `validate_rate` extension (deals slice only):** (a) accept the
`{scope, countries, rate}` form on `overrides` entries (today `validate_rate:333` requires non-empty `products`);
(b) whitelist a `floors` key + a light shape check (mirrors the overrides-entry check but with `floor` instead of
`rate`). Both are additive and parity-safe — no existing spec uses scope-form or floors; existing callers
unchanged; `resolve_rate` is NOT modified (scope/floors entries are inherently reader-invisible). This is the
small validator addition, NOT the rejected "per-entry rate_type in resolve_rate" keystone change.

**scenario_ops obligations (move write-path with read-path, per slice — do NOT split across commits):**
- **Exempt slice:** `op_set_exempt` (steel/aluminum) must write the `by_country = 0` entry instead of the residual
  blob `*_exempt` field, AND census-expand ISO/EU at write time (the old path expanded at READ via `is_232_exempt`;
  the new path must expand at write or the exemption silently no-ops). The existing test asserting set_exempt
  writes the blob (`tests/test_scenario_ops.R:~162-164`) must be **rewritten** to assert `by_country`.
- **Deals slice:** `op_disable` ALREADY drains the deal tibbles (`scenario_ops.R:217-219`) — it must be repointed
  to clear the new `overrides`(scope)/`floors` fields in lockstep, or `disable(section_232)` silently stops
  draining deals. (The deals design's "no scenario op touches deals" was FALSE — adversarial catch.)
- **has_232 stays a residual gate** in ALL slices (no program added/removed → the three formulas stay in
  lockstep untouched). `auto_has_deals`/`auto_has_parts`/`wood_furniture_rate`/derivatives stay on the blob (S3 /
  decision-8). `extract_section232_rates` (parser) is unchanged — the adapter re-packages its output, as in S1a/S1b.

**Gate-red protocol:** a red gate means a re-packaging detail drifted (application/merge order, census/EU
expansion, strict-`<` boundary, or the floor base regressed to post-MFN) — re-derive the detail; do NOT reach for
a schema change. Before gating the deals slice, hand-re-derive the floor math on UK auto parts (floor 0.10), EU
auto vehicles (floor 0.15), UK wood (surcharge 0.10) vs the golden snapshot.

**S3 plan:**
- **UK annex deal** (`06:2134-2145`, a `case_when` gating UK × annex-1a/1b × chapters 72/73/76): delete only
  after confirming the S2 steel/aluminum `overrides` reproduce it exactly (product set = {annex members} ×
  {those chapters}, override precedence wins). Otherwise it's a silent double-count or gap.
- **Taiwan civil-aircraft exemption** (`06:2964-2995`): zeros `rate_232` for Taiwan aircraft HTS **only when
  `s232_annex` is not NA** (metals annex) — so a blanket Taiwan-aircraft `rate=0` override would WRONGLY zero
  auto/MHD/wood 232 duties on the same HTS. `resolve_rate(product, country)` has no annex context, so keep the
  post-calc gate structure but source the product list/rate from the spec instead of the hardcoded loop.
- Then drain the residual blob to just what decision-8 blends/derivatives still read.
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

- **2026-06-05 — Plank 4a S2 DESIGN LOCKED (no code yet).** Settled the hardest stage via a fan-out workflow
  (5 parallel mappers → 1 architecture-decision agent → 4 slices each designed then adversarially parity-
  verified, 14 agents) + two decisions from John. Outcome: (1) **blanket slices (exempt / metal HTS overrides /
  config exemptions) → ONE merged `by_country`**, NOT `overrides` — the adversarial pass proved a per-country
  read is `resolve_rate(product=NULL)`, which short-circuits both override forms (corrects the plan doc). (2)
  **Deals split by CONCEPT** (John rejected the lumped "deals" bucket): flat product×country surcharge deals →
  `overrides` scope-form `{scope, countries, rate}`; floor deals → a NEW `floors` field `{scope, countries,
  floor}`; the calc expands the scope label at run time and keeps the floor/surcharge math (decision 8), so
  products stay calc-time (no new parity surface). The ONLY Plank-0 touch = an additive `validate_rate`
  extension (accept the scope-form on `overrides` + whitelist `floors`); `resolve_rate` untouched (scope/floors
  entries are reader-invisible). Adversarial pass caught two real blockers the design agent missed: storing
  deals under any existing layer crashes `validate_rate` (whitelist + the overrides `products` requirement), and
  `op_disable` already drains the deal tibbles (`scenario_ops.R:217-219`) so it must be repointed in lockstep.
  Slice order cheapest→riskiest: HTS overrides → exempt (steel/alum only; `auto_exempt` stays on blob, zero
  observable effect) → config exemptions → deals. Full locked design in the "S2 LOCKED DESIGN" subsection.
  **Next = implement slice 1 (HTS overrides) in a worktree, unit-test, hand to John for the live parity gate.**
- **2026-06-05 — Plank 4a S1a + S1b landed (both parity GREEN 47/47); gate-tooling bug fixed.**
  Read-path decision = FULL REPOINT (no shim). **S1a** (`2a2232e`): blanket steel/aluminum/auto base
  rates → each program's `rate$default`; new `s232_spec_rate()` helper (spec-first, blob-fallback for
  specs-less callers). **S1b** (`307401b`): heading programs (copper/mhd/wood/semi) + a dormant
  `pharmaceuticals` program de-blobbed; `compute_heading_gates`/`resolve_heading_rate`/
  `.s232_recompute_has_232` repointed to read program rates off the spec (`HEADING_RESOLVED_PROGRAM`
  map); non-rate gate inputs stay on the residual blob. scenario_ops `set_rate`/`disable` now mutate
  `rate$default`. Both bit-exact at baseline by construction; unit gates green (adapter 31/31,
  scenario_ops 48/48, spec 19/19, parity 22/22). Parity: S1a array `13807774`→compare `13808487`
  (47/47); S1b array `13809706`→compare `13810632` (47/47). **Gate fix** (`134759f`, src/parity.R): the
  `--unweighted` build drops the un-gated weighted/ETR columns the golden carries; `compare_parity` was
  false-flagging them as `schema_missing_column` — now skipped (pattern `^weighted_etr|^etr_|_imports_b$`).
  This was a pre-existing gather-refactor gate bug surfaced by the S1a daily artifacts (4/8/1/1 "violations"
  = exactly the absent weighted columns). **Workflow learned:** the build sources LIVE src at task runtime,
  so develop the next stage in a worktree + cherry-pick once the prior build is done (never edit live src
  mid-build). **Next = S2** (country deals → overrides/by_country; floor_static; the highest-risk stage) —
  detailed handoff in the "Plank 4a — execution notes & handoff" subsection above.
- **2026-06-05 — Daily gather aggregation pushed into the array tasks.** Follow-up
  to the no-monolith gather: each `scripts/build_revision.R` task now writes a
  small `daily_part_<rev>.rds` from the in-memory snapshot after the snapshot is
  built. `build_gather.R` validates the part cache against final intervals,
  weight mode, and snapshot mtimes, then binds it; stale/missing parts (including
  scheduled revisions that shorten the tip interval) fall back to the existing
  snapshot-streaming path. Verified by full `GATHER_ARGS="--unweighted"` Slurm
  run: array `13805179` completed 43/43 tasks (`0:0`; heaviest tasks 3:31-3:36),
  gather `13805180` used `43 precomputed daily aggregate part(s)` and completed
  in 4:11. End-to-end from first array task start to gather completion: 12:54
  including scheduler gaps.
- **2026-06-05 — Gather monolith removed from the check/publish path.** Follow-up
  to the Plank-3 parity bottleneck: daily series already had a per-snapshot
  streaming path, and the quality report was rewritten to stream the same
  `snapshot_*.rds` files instead of loading the combined `rate_timeseries.rds`.
  The deleted legacy `08_weighted_etr.R` path was the last old ETR duplicate; the
  live daily aggregates remain import-weighted. `build_gather.R` now streams
  daily + quality, writes fresh `metadata.rds`, and never assembles the 204M-row
  monolith. `publish_internal.R` publishes per-interval snapshot parquets directly
  (`valid_from=*/rates.parquet`), and `publish_git.R` publishes only daily CSVs.
  Gates: tier-2 gather `13800246` (6:34) + parity `13800247` GREEN 47/47;
  quality equivalence `13800647` proved `STREAMING == MONOLITH`; final no-monolith
  gather `13801477` completed in 6:11 (parity `13801478` submitted).
- **2026-06-05 — Plank 3 landed (parity GREEN).** Section 122 de-blobbed: the blanket rate
  migrated from the `rate$resolved` blob into the structured `rate$default` layer
  (`rate_type='surcharge'`); calc reads it via `resolve_rate(...)$value`, gating on `value>0`
  (≡ old `has_s122`). scenario_ops: new `DEFAULT_RATE_AUTHORITIES` category for s122 (set_rate
  → `rate$default`, disable → 0); s232 stays a blob until 4a. Dropped the dead
  `s122_rates_from_specs` accessor. Commit `d5ed486` (impl) — unit gate 47+19+21 (job 13797714);
  parity 47/47 within tolerance vs tests/golden/9f9837d (array 13797729 → gather 13797730
  `--unweighted` → parity 13797778; snapshot-only early check 13798477 also 43/43). Per John's
  "no half-measures" call this was the FULL structural de-blob, not a Plank-2-style close-out —
  it's the template for s232 (4a) and IEEPA (4b). Observed (separate follow-up, not done): the
  gather still materializes the 204M-row `rate_timeseries.rds` and feeds it WHOLE to the daily
  series, even though a streaming per-snapshot daily path (`build_daily_aggregates_streaming`,
  perf Phase 1) + per-interval publish split already exist — repointing the gather's daily call
  to the streaming path would drop peak memory ~48GB→~1.2GB and is parity-safe (output documented
  identical). See [[gather-monolith-vs-streaming]].
- **2026-06-05 — Plank 2 landed (parity trivially GREEN; no rebuild).** Section 201's
  spec-driven country scope was already shipped on the 301cs branch as "Phase 2e" and is
  present at `9f9837d` (the golden), so the build path is byte-identical and a rebuild would
  be a guaranteed no-op — verified `resolve_country_scope({all, exclude: Canada})` ==
  `setdiff(countries, Canada)` bit-for-bit, and confirmed via `git show 9f9837d` that both the
  adapter scope and the `06:` calc read predate the golden. Net-new work: closed the scenario
  test coverage gap (201 rescope + disable in `tests/test_scenario_ops.R`, mirroring 301),
  documented the Plank-7 fallback coupling on the `06:` hook, and reconciled the plan
  ("`disable:` vocab" lives in `scenario_ops.R::SCOPE_DRIVEN_AUTHORITIES`, not the yaml; the
  specs-less fallback is RETAINED until Plank 7, same as Plank 1). Gate:
  `sbatch scripts/submit_plank2_tests.sh` (scenario_ops + spec + adapter, pure-logic).
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
