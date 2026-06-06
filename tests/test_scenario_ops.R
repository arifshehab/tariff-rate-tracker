# =============================================================================
# scenario_ops unit tests
# =============================================================================
# Pure-logic checks for src/scenario_ops.R — the operations engine. No model data.
# Verifies the flagship re-scope (301 -> China+Vietnam), disable, set_active,
# copy-on-modify isolation, and fail-loud on unsupported/invalid ops.
# Usage: Rscript tests/test_scenario_ops.R
# =============================================================================

suppressPackageStartupMessages(library(here))
source(here('src', 'authority_spec.R'))
source(here('src', 'scenario_ops.R'))
source(here('src', 'new_coverage.R'))   # Phase 8: collect_seeded_programs / resolve_product_scope

pass <- 0L
check <- function(cond, msg) {
  if (!isTRUE(cond)) stop('FAILED: ', msg, call. = FALSE)
  pass <<- pass + 1L; cat('  ok:', msg, '\n')
}
expect_error <- function(expr, msg) {
  err <- tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
  if (is.null(err)) stop('FAILED (expected error): ', msg, call. = FALSE)
  pass <<- pass + 1L; cat('  ok (errored):', msg, '\n')
}

# --- baseline spec set (China-scoped 301, all-except-Canada 201, a 232) -------
specs <- authority_spec_set(
  authority_spec('section_301', stacking = list(class = 'additive'),
    programs = list(authority_program('s301', country_scope = list(include = '5700')))),
  authority_spec('section_201', stacking = list(class = 'additive'),
    programs = list(authority_program('s201', country_scope = list(include = 'all', exclude = '1220')))),
  authority_spec('section_232', stacking = list(class = 'primary_metal'),
    programs = list(authority_program('steel', stacking = list(class = 'primary_metal'),
                                      metal = list(type = 'steel'))))
)

cat('--- empty ops is a no-op ("baseline = the empty scenario") ---\n')
check(identical(apply_operations(specs, list()), specs), 'empty operations list returns specs unchanged')

cat('\n--- set_country_scope: the flagship 301 -> China + Vietnam ---\n')
specs2 <- apply_operations(specs, list(
  list(op = 'set_country_scope', authority = 'section_301', program = 's301',
       country_scope = list(include = c('5700', '5520')))))
check(identical(specs2[['section_301']]$programs[[1]]$country_scope$include, c('5700', '5520')),
      '301 re-scoped to China + Vietnam')
check(identical(specs[['section_301']]$programs[[1]]$country_scope$include, '5700'),
      'original specs NOT mutated (copy-on-modify isolation)')

cat('\n--- disable empties the scope (scope-driven authority) ---\n')
specs3 <- apply_operations(specs, list(list(op = 'disable', authority = 'section_301')))
check(identical(specs3[['section_301']]$programs[[1]]$country_scope$include, character(0)),
      'disable section_301 -> empty country scope')

cat('\n--- set_active sets the window ---\n')
specs4 <- apply_operations(specs, list(
  list(op = 'set_active', authority = 'section_301', program = 's301',
       active = list(until = as.Date('2027-01-01')))))
check(identical(specs4[['section_301']]$programs[[1]]$active$until, as.Date('2027-01-01')),
      'set_active sets program active.until')

cat('\n--- Plank 2: Section 201 is scope-driven too (rescope + disable) ---\n')
# The calc reads 201 country scope off the spec (06: Phase 2e), so the same scope
# verbs that drive 301 must drive 201. Baseline 201 = all-except-Canada
# (country_scope$exclude = '1220'); re-scope it to an explicit allow-list:
specs201 <- apply_operations(specs, list(
  list(op = 'set_country_scope', authority = 'section_201', program = 's201',
       country_scope = list(include = c('5700', '5520')))))
check(identical(specs201[['section_201']]$programs[[1]]$country_scope,
                list(include = c('5700', '5520'))),
      '201 re-scoped to an explicit allow-list (drops the all-except-Canada default)')
check(identical(specs[['section_201']]$programs[[1]]$country_scope$exclude, '1220'),
      'original 201 spec NOT mutated (copy-on-modify isolation)')
specs201d <- apply_operations(specs, list(list(op = 'disable', authority = 'section_201')))
check(identical(specs201d[['section_201']]$programs[[1]]$country_scope$include, character(0)),
      'disable section_201 -> empty country scope (calc applies it to no countries)')

cat('\n--- fail-loud: unsupported / invalid ops never silently no-op ---\n')
expect_error(apply_operations(specs, list(
  list(op = 'set_country_scope', authority = 'section_232',
       country_scope = list(include = 'all')))),
  'scope op on non-scope-driven authority (232) errors')
expect_error(apply_operations(specs, list(list(op = 'add_program', authority = 'section_232'))),
  'add_program without a `program` record errors')
expect_error(apply_operations(specs, list(
  list(op = 'set_floor', authority = 'section_301', rate = 0.1))),
  'unsupported verb (set_floor) errors — deferred follow-up')
expect_error(apply_operations(specs, list(
  list(op = 'set_country_scope', authority = 'no_such', country_scope = list(include = 'all')))),
  'unknown authority errors')
expect_error(apply_operations(specs, list(list(op = 'set_country_scope', authority = 'section_301'))),
  'missing country_scope errors')

# =============================================================================
# Phase 6d — set_rate / set_exempt / disable on the rate-driven authorities
# =============================================================================
cat('\n--- Phase 6d: set_rate / set_exempt / disable (rate-driven authorities) ---\n')

# S1b: section_232 is multi-program — each program's rate lives in rate$default; the
# NON-rate fields (flags/derivatives/deals/exempts/has_232) are a residual blob on
# programs[[1]] (steel). Mirrors the adapter's S1a+S1b shape.
s232_residual <- list(
  auto_has_deals = FALSE, auto_has_parts = FALSE, wood_furniture_rate = 0,
  aluminum_derivative_rate = 0, steel_derivative_rate = 0,
  steel_exempt = character(0), aluminum_exempt = '1220', auto_exempt = character(0),
  auto_deal_rates = data.frame(), wood_deal_rates = data.frame(), has_232 = TRUE)
mk_s232_prog <- function(id, default, type = 'none') authority_program(
  id = id,
  stacking = list(class = if (type == 'none') 'primary_full' else 'primary_metal'),
  metal = list(type = type),
  rate = list(default = default, rate_type = 'surcharge'))
mk_s232 <- function(defaults = list(), residual = s232_residual) {
  progs <- list(
    mk_s232_prog('steel',           defaults$steel    %||% 0, 'steel'),
    mk_s232_prog('aluminum',        defaults$aluminum %||% 0, 'aluminum'),
    mk_s232_prog('copper',          defaults$copper   %||% 0, 'copper'),
    mk_s232_prog('autos',           defaults$autos    %||% 0),
    mk_s232_prog('mhd',             defaults$mhd      %||% 0),
    mk_s232_prog('wood',            defaults$wood     %||% 0),
    mk_s232_prog('semiconductors',  defaults$semi     %||% 0),
    mk_s232_prog('pharmaceuticals', defaults$pharma   %||% 0))
  progs[[1]]$rate$resolved <- residual   # residual blob rides on steel (programs[[1]])
  authority_spec('section_232', stacking = list(class = 'primary_metal'), programs = progs)
}
.s232p     <- function(specs, id) { pr <- specs[['section_232']]$programs
  pr[[which(vapply(pr, function(p) identical(p$id, id), logical(1)))]] }
.s232_resid <- function(specs) specs[['section_232']]$programs[[1]]$rate$resolved

rspecs <- authority_spec_set(
  mk_s232(list(steel = 0.25, aluminum = 0.10)),
  # Plank 4b: IEEPA de-blobbed into structured per-country layers.
  authority_spec('ieepa_reciprocal', stacking = list(class = 'content_split'),
    programs = list(authority_program('reciprocal', rate = list(
      by_country         = c('5700' = 0.10, '3510' = 0.50, '4279' = 0.15),
      by_country_type    = c('5700' = 'surcharge', '3510' = 'surcharge', '4279' = 'floor'),
      by_country_eo_rate = c('5700' = 0, '3510' = 0.40, '4279' = 0),
      by_country_eo_ch99 = c('5700' = NA, '3510' = '9903.01.77', '4279' = NA),
      default_unlisted_rate = 0.10,
      default_unlisted_exclude = c('1220', '2010'))))),
  authority_spec('ieepa_fentanyl', stacking = list(class = 'content_split'),
    programs = list(authority_program('fentanyl', rate = list(
      by_country = c('5700' = 0.10, '1220' = 0.35, '2010' = 0.25),
      carveouts  = list(ch99_code = '9903.01.13', census_code = '1220', rate = 0.10))))),
  authority_spec('section_122', stacking = list(class = 'content_split'),
    programs = list(authority_program('s122', rate = list())))   # Plank 3: dormant => no rate$default
)

b <- apply_operations(rspecs, list(
  list(op = 'set_rate', authority = 'section_232', program = 'steel', rate = 0.50)))
check(identical(.s232p(b, 'steel')$rate$default, 0.50),
      'set_rate 232/steel -> rate$default 0.50 (de-blobbed, S1b)')
check(isTRUE(.s232_resid(b)$has_232),
      'has_232 (residual gate) stays TRUE after a steel bump')
check(identical(.s232p(rspecs, 'steel')$rate$default, 0.25),
      'original specs NOT mutated (copy-on-modify isolation)')

# set_rate turns a dormant metal ON -> has_232 flips FALSE->TRUE (recompute reads the spec default)
off_res <- s232_residual; off_res$has_232 <- FALSE
offspec <- authority_spec_set(mk_s232(list(), residual = off_res))   # all defaults 0, gate OFF
con <- apply_operations(offspec, list(
  list(op = 'set_rate', authority = 'section_232', program = 'copper', rate = 0.50)))
check(identical(.s232p(con, 'copper')$rate$default, 0.50),
      'set_rate 232/copper -> rate$default 0.50 (dormant metal activated)')
check(isTRUE(.s232_resid(con)$has_232),
      'has_232 flips FALSE->TRUE when a dormant metal (copper) is turned on')

s <- apply_operations(rspecs, list(list(op = 'set_rate', authority = 'section_122', rate = 0.10)))
check(identical(s[['section_122']]$programs[[1]]$rate$default, 0.10),
      'set_rate s122 -> rate$default 0.10 (de-blobbed; calc gate value>0 turns it ON)')
check(is.null(s[['section_122']]$programs[[1]]$rate$resolved),
      's122 set_rate writes the structured rate$default layer, not a resolved blob (Plank 3)')

e <- apply_operations(rspecs, list(
  list(op = 'set_exempt', authority = 'section_232', program = 'steel', countries = c('1220', '2010'))))
check(identical(.s232p(e, 'steel')$rate$by_country, stats::setNames(c(0, 0), c('1220', '2010'))),
      'set_exempt 232/steel -> rate$by_country {Canada,Mexico} = 0 (de-blobbed to by_country, S2)')
check(identical(.s232_resid(e)$steel_exempt, character(0)),
      'set_exempt 232/steel no longer writes the residual blob steel_exempt (S2)')

d <- apply_operations(rspecs, list(list(op = 'disable', authority = 'section_232')))
check(identical(.s232p(d, 'steel')$rate$default, 0) && identical(.s232p(d, 'copper')$rate$default, 0),
      'disable 232 zeros every program rate$default')
check(isFALSE(.s232_resid(d)$has_232),
      'disable 232 -> has_232 FALSE (residual gate)')

# S2 deals: disable also clears the autos/wood deal layers (overrides scope-form + floors).
rspecs_deals <- rspecs
.au <- which(vapply(rspecs_deals[['section_232']]$programs,
                    function(p) identical(p$id, 'autos'), logical(1)))
rspecs_deals[['section_232']]$programs[[.au]]$rate$overrides <-
  list(list(scope = 'auto_vehicles', countries = '4120', rate = 0.075))
rspecs_deals[['section_232']]$programs[[.au]]$rate$floors <-
  list(list(scope = 'auto_vehicles', countries = '4280', floor = 0.15))
dd <- apply_operations(rspecs_deals, list(list(op = 'disable', authority = 'section_232')))
check(is.null(.s232p(dd, 'autos')$rate$overrides) && is.null(.s232p(dd, 'autos')$rate$floors),
      'disable 232 clears the autos deal layers (rate$overrides + rate$floors) (S2 deals)')

# section_122 (Plank 3): set_rate then disable round-trips the rate$default scalar.
d122 <- apply_operations(rspecs, list(
  list(op = 'set_rate', authority = 'section_122', rate = 0.15),
  list(op = 'disable',  authority = 'section_122')))
check(identical(d122[['section_122']]$programs[[1]]$rate$default, 0),
      'disable s122 zeros rate$default (calc gate value>0 -> OFF)')

cat('\n--- Phase 6d: fail-loud guards ---\n')
expect_error(apply_operations(rspecs, list(list(op = 'set_rate', authority = 'section_232', rate = 0.5))),
  'set_rate 232 without `program` errors')
expect_error(apply_operations(rspecs, list(
  list(op = 'set_rate', authority = 'section_232', program = 'unobtanium', rate = 0.5))),
  'set_rate 232 with unknown program errors')
expect_error(apply_operations(rspecs, list(list(op = 'set_rate', authority = 'ieepa_reciprocal', rate = 0.5))),
  'set_rate ieepa without `country` errors (Plank 4b/6)')
expect_error(apply_operations(rspecs, list(list(op = 'set_country_scope', authority = 'ieepa_fentanyl'))),
  'set_country_scope ieepa without `country_scope` errors')
expect_error(apply_operations(rspecs, list(
  list(op = 'set_exempt', authority = 'section_232', program = 'copper', countries = '1220'))),
  'set_exempt on a program with no exemption list (copper) errors')

cat('\n--- Codex F1: a 232 rate op invalidates the cached heading_gates attr ---\n')
# The calc reads attr(spec,'heading_gates') and SKIPS FALSE-gated headings, with a
# `%||% compute_heading_gates(s232_rates)` fallback that recomputes from the mutated
# payload when the cache is absent. A set_rate/disable that changes a heading rate
# MUST drop the stale cache so the recompute reflects it — else a scenario that
# activates copper is silently skipped (the bug Codex F1 caught).
gated <- rspecs
attr(gated[['section_232']], 'heading_gates') <- list(copper = FALSE, semiconductors = FALSE)
g1 <- apply_operations(gated, list(
  list(op = 'set_rate', authority = 'section_232', program = 'copper', rate = 0.50)))
check(is.null(attr(g1[['section_232']], 'heading_gates', exact = TRUE)),
      'set_rate 232/copper drops the stale heading_gates cache (calc then recomputes copper=TRUE)')
g2 <- apply_operations(gated, list(list(op = 'disable', authority = 'section_232')))
check(is.null(attr(g2[['section_232']], 'heading_gates', exact = TRUE)),
      'disable 232 drops the stale heading_gates cache (calc then recomputes gates OFF)')
g3 <- apply_operations(gated, list(list(op = 'set_rate', authority = 'section_122', rate = 0.10)))
check(identical(attr(g3[['section_232']], 'heading_gates', exact = TRUE),
                list(copper = FALSE, semiconductors = FALSE)),
      's122 set_rate leaves the 232 gate cache untouched (different authority)')

# =============================================================================
# Plank 4b / 6 — IEEPA scenario verbs (set_rate per-country / set_country_scope /
# disable), enabled by the de-blobbed structured rate. Baseline = empty ops, so
# these affect only counterfactual runs; parity is untouched (UNIT-only).
# =============================================================================
cat('\n--- Plank 4b/6: IEEPA scenario verbs ---\n')
.recip <- function(s) s[['ieepa_reciprocal']]$programs[[1]]$rate
.fent  <- function(s) s[['ieepa_fentanyl']]$programs[[1]]$rate

# disable: clears every rate layer -> calc gate reads OFF
dr <- apply_operations(rspecs, list(list(op = 'disable', authority = 'ieepa_reciprocal')))
check(is.null(.recip(dr)$by_country) && is.null(.recip(dr)$default_unlisted_rate) &&
        is.null(.recip(dr)$by_country_type) && is.null(.recip(dr)$by_country_eo_rate),
      'disable ieepa_reciprocal clears all rate layers (calc has_active_ieepa -> FALSE)')
df <- apply_operations(rspecs, list(list(op = 'disable', authority = 'ieepa_fentanyl')))
check(is.null(.fent(df)$by_country) && is.null(.fent(df)$carveouts),
      'disable ieepa_fentanyl clears by_country + carveouts (calc has_fentanyl -> FALSE)')

# set_rate per-country: writes by_country[country]; reciprocal is a clean flat surcharge
sr <- apply_operations(rspecs, list(
  list(op = 'set_rate', authority = 'ieepa_reciprocal', country = '5700', rate = 0.30)))
check(isTRUE(all.equal(unname(.recip(sr)$by_country['5700']), 0.30)) &&
        .recip(sr)$by_country_type['5700'] == 'surcharge' &&
        isTRUE(all.equal(unname(.recip(sr)$by_country_eo_rate['5700']), 0)) &&
        is.na(unname(.recip(sr)$by_country_eo_ch99['5700'])),
      'set_rate ieepa_reciprocal/China -> by_country 0.30, clean surcharge (eo dropped)')
check(isTRUE(all.equal(unname(.recip(sr)$by_country['3510']), 0.50)) &&
        isTRUE(all.equal(unname(.recip(sr)$by_country_eo_rate['3510']), 0.40)),
      'set_rate leaves other countries (Brazil 0.50, eo 0.40) untouched')
check(isTRUE(all.equal(unname(.recip(rspecs)$by_country['5700']), 0.10)),
      'original rspecs NOT mutated (copy-on-modify isolation)')

# set_rate for a NEW country grows by_country + the parallel companion maps
srn <- apply_operations(rspecs, list(
  list(op = 'set_rate', authority = 'ieepa_reciprocal', country = '9999', rate = 0.20)))
check(isTRUE(all.equal(unname(.recip(srn)$by_country['9999']), 0.20)) &&
        .recip(srn)$by_country_type['9999'] == 'surcharge' &&
        '9999' %in% names(.recip(srn)$by_country_eo_rate),
      'set_rate ieepa for a NEW country grows by_country + parallel companion maps')

srf <- apply_operations(rspecs, list(
  list(op = 'set_rate', authority = 'ieepa_fentanyl', country = '5700', rate = 0.50)))
check(isTRUE(all.equal(unname(.fent(srf)$by_country['5700']), 0.50)),
      'set_rate ieepa_fentanyl/China -> by_country 0.50')

# set_country_scope (exclude): drop countries -> 0; reciprocal also bars them from baseline
se <- apply_operations(rspecs, list(
  list(op = 'set_country_scope', authority = 'ieepa_reciprocal',
       country_scope = list(exclude = '5700'))))
check(!('5700' %in% names(.recip(se)$by_country)) &&
        '5700' %in% .recip(se)$default_unlisted_exclude,
      'set_country_scope exclude China: dropped from by_country + added to baseline exclude')
check(!('5700' %in% names(.recip(se)$by_country_type)),
      'exclude drops the parallel companion maps too (stay in lockstep)')

# set_country_scope (include={set}): keep only listed; reciprocal baseline off
si <- apply_operations(rspecs, list(
  list(op = 'set_country_scope', authority = 'ieepa_reciprocal',
       country_scope = list(include = '3510'))))
check(identical(names(.recip(si)$by_country), '3510') && is.null(.recip(si)$default_unlisted_rate),
      'set_country_scope include={Brazil}: by_country kept to Brazil, baseline turned off')

# fentanyl exclude also drops the carve-out rows for that census code
sfe <- apply_operations(rspecs, list(
  list(op = 'set_country_scope', authority = 'ieepa_fentanyl',
       country_scope = list(exclude = '1220'))))
check(!('1220' %in% names(.fent(sfe)$by_country)) && is.null(.fent(sfe)$carveouts),
      'set_country_scope exclude Canada (fentanyl): drops by_country + its carve-out rows')

# =============================================================================
# Phase 8 — add_program (new coverage) + the no-Ch99 seeder's pure helpers
# =============================================================================
cat('\n--- Phase 8: add_program appends a new-coverage program ---\n')
nc_specs <- authority_spec_set(
  authority_spec('section_301', stacking = list(class = 'additive'),
    programs = list(authority_program('s301', country_scope = list(include = '5700')))),
  authority_spec('other', stacking = list(class = 'additive'),
    programs = list(authority_program('other', country_scope = list(include = 'all'))))
)

# A clearly-SYNTHETIC drone tariff: 50% on HTS prefix 8806, all countries.
drone_op <- list(op = 'add_program', authority = 'other',
                 program = list(id = 'drone_synthetic',
                                rate = list(flat = 0.50),
                                product_scope = list(prefixes = '8806'),
                                country_scope = list(include = 'all')))
np <- apply_operations(nc_specs, list(drone_op))
check(length(np[['other']]$programs) == 2L, 'add_program appended a program to `other`')
added <- np[['other']]$programs[[2]]
check(identical(added$id, 'drone_synthetic'), 'added program has the given id')
check(identical(added$rate$flat, 0.50), 'added program carries rate$flat')
check(identical(nc_specs[['other']]$programs |> length(), 1L),
      'original specs NOT mutated (copy-on-modify isolation)')

cat('\n--- Phase 8: collect_seeded_programs finds only flat-rate programs ---\n')
check(length(collect_seeded_programs(nc_specs)) == 0L,
      'baseline (no flat-rate programs) => collect_seeded_programs empty (dormant)')
seeded <- collect_seeded_programs(np)
check(length(seeded) == 1L && identical(seeded[[1]]$id, 'drone_synthetic'),
      'after add_program => one seeded program, tagged with .authority')
check(identical(seeded[[1]]$.authority, 'other'), 'seeded program carries its authority name')

cat('\n--- Phase 8: resolve_product_scope (prefixes / all / list) ---\n')
prods <- data.frame(hts10 = c('8806100000', '8806900000', '8525890000', '7208100000'),
                    base_rate = 0, stringsAsFactors = FALSE)
check(setequal(resolve_product_scope(list(prefixes = '8806'), prods),
               c('8806100000', '8806900000')), 'prefixes 8806 -> the two 8806 HTS10s')
check(length(resolve_product_scope(list(include = 'all'), prods)) == 4L, 'include=all -> every product')
check(setequal(resolve_product_scope(list(list = c('7208100000', '9999999999')), prods),
               '7208100000'), 'explicit list -> intersection with the product universe')

cat('\n--- Phase 8: fail-loud guards ---\n')
expect_error(apply_operations(nc_specs, list(list(op = 'add_program', authority = 'other',
  program = list(id = 'no_rate', product_scope = list(include = 'all'))))),
  'add_program without rate$flat errors')
expect_error(apply_operations(np, list(drone_op)),
  'add_program with a duplicate program id errors')
expect_error(resolve_product_scope(list(chapters = '88'), prods),
  'unrecognized product_scope errors (never silently covers nothing)')

cat('\n--- Codex F8: add_program without `authority` defaults to `other` ---\n')
np2 <- apply_operations(nc_specs, list(
  list(op = 'add_program',
       program = list(id = 'drone_no_auth', rate = list(flat = 0.25),
                      product_scope = list(prefixes = '8806'), country_scope = list(include = 'all')))))
check(length(np2[['other']]$programs) == 2L, 'add_program with no `authority` landed on `other`')
check(identical(np2[['other']]$programs[[2]]$id, 'drone_no_auth'),
      'the defaulted-to-other program carries the given id')
# every other verb still requires authority
expect_error(apply_operations(specs, list(list(op = 'disable'))),
  'a non-add_program verb without `authority` still errors')

# =============================================================================
# Plank 5d — set_stacking. Mutates a spec's stacking {class, exceptions}, which
# Plank 5b made load-bearing in the calc (stacking_policy_from_specs). Baseline =
# empty ops, so this affects only counterfactual runs; parity untouched (UNIT-only).
# =============================================================================
cat('\n--- Plank 5d: set_stacking (authority-level class) ---\n')
s_cs <- apply_operations(specs, list(list(op = 'set_stacking', authority = 'section_301',
                                          stacking = list(class = 'content_split'))))
check(identical(s_cs[['section_301']]$stacking$class, 'content_split'),
      'set_stacking flips section_301 authority class -> content_split')
check(identical(specs[['section_301']]$stacking$class, 'additive'),
      'original specs unchanged (copy-on-modify isolation)')

cat('\n--- set_stacking: program-level write leaves the authority class intact ---\n')
s_pg <- apply_operations(specs, list(list(op = 'set_stacking', authority = 'section_232',
                                          program = 'steel', stacking = list(class = 'content_split'))))
check(identical(s_pg[['section_232']]$programs[[1]]$stacking$class, 'content_split'),
      'set_stacking on section_232/steel writes the program-level class')
check(identical(s_pg[['section_232']]$stacking$class, 'primary_metal'),
      'the section_232 authority-level class is untouched by the program-level set')

cat('\n--- set_stacking: modifyList top-level merge (exceptions-only preserves class) ---\n')
s_ex <- apply_operations(specs, list(list(op = 'set_stacking', authority = 'section_301',
                                          stacking = list(exceptions = setNames(list('additive'), '5700')))))
check(identical(s_ex[['section_301']]$stacking$class, 'additive'),
      'exceptions-only set preserves the existing class (modifyList)')
check(identical(s_ex[['section_301']]$stacking$exceptions, setNames(list('additive'), '5700')),
      'set_stacking writes the exceptions map')

cat('\n--- set_stacking: fail-loud guards ---\n')
expect_error(apply_operations(specs, list(list(op = 'set_stacking', authority = 'section_301',
  stacking = list(class = 'bogus')))),
  'invalid stacking.class errors via validate_spec_set')
expect_error(apply_operations(specs, list(list(op = 'set_stacking', authority = 'section_301',
  stacking = list(class = 'primary_metal')))),
  'primary_metal on a non-metal authority errors (program lacks metal.type)')
expect_error(apply_operations(specs, list(list(op = 'set_stacking', authority = 'nope',
  stacking = list(class = 'additive')))),
  'set_stacking on an unknown authority errors')
expect_error(apply_operations(specs, list(list(op = 'set_stacking', authority = 'section_301'))),
  'set_stacking without `stacking` errors')

cat(sprintf('\nALL %d SCENARIO_OPS ASSERTIONS PASSED\n', pass))
