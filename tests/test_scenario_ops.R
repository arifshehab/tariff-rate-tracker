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
  list(op = 'disable', authority = 'ieepa_reciprocal'))),
  'disable on embed-backed authority (ieepa) errors — deferred to Phase 7')
expect_error(apply_operations(specs, list(
  list(op = 'set_country_scope', authority = 'no_such', country_scope = list(include = 'all')))),
  'unknown authority errors')
expect_error(apply_operations(specs, list(list(op = 'set_country_scope', authority = 'section_301'))),
  'missing country_scope errors')

# =============================================================================
# Phase 6d — set_rate / set_exempt / disable on the rate-driven authorities
# =============================================================================
cat('\n--- Phase 6d: set_rate / set_exempt / disable (rate-driven authorities) ---\n')

# A spec set carrying resolved rate payloads (the thin cut: programs[[1]]$rate$resolved).
s232_resolved <- list(
  steel_rate = 0.25, aluminum_rate = 0.10, copper_rate = 0, auto_rate = 0, mhd_rate = 0,
  wood_rate = 0, wood_furniture_rate = 0, semi_rate = 0,
  aluminum_derivative_rate = 0, steel_derivative_rate = 0, auto_has_deals = FALSE,
  steel_exempt = character(0), aluminum_exempt = '1220', auto_exempt = character(0),
  auto_deal_rates = data.frame(), wood_deal_rates = data.frame(), has_232 = TRUE)
rspecs <- authority_spec_set(
  authority_spec('section_232', stacking = list(class = 'primary_metal'),
    programs = list(authority_program('steel', stacking = list(class = 'primary_metal'),
      metal = list(type = 'steel'), rate = list(resolved = s232_resolved)))),
  authority_spec('ieepa_reciprocal', stacking = list(class = 'content_split'),
    programs = list(authority_program('reciprocal', rate = list(resolved = data.frame(country = '5700', rate = 0.10))))),
  authority_spec('section_122', stacking = list(class = 'content_split'),
    programs = list(authority_program('s122', rate = list())))   # Plank 3: dormant => no rate$default
)

b <- apply_operations(rspecs, list(
  list(op = 'set_rate', authority = 'section_232', program = 'steel', rate = 0.50)))
check(identical(b[['section_232']]$programs[[1]]$rate$resolved$steel_rate, 0.50),
      'set_rate 232/steel -> 0.50')
check(isTRUE(b[['section_232']]$programs[[1]]$rate$resolved$has_232),
      'has_232 stays TRUE after a steel bump')
check(identical(rspecs[['section_232']]$programs[[1]]$rate$resolved$steel_rate, 0.25),
      'original specs NOT mutated (copy-on-modify isolation)')

# set_rate turns a dormant metal ON -> has_232 flips FALSE->TRUE
off <- s232_resolved; off$steel_rate <- 0; off$aluminum_rate <- 0; off$has_232 <- FALSE
offspec <- authority_spec_set(authority_spec('section_232', stacking = list(class = 'primary_metal'),
  programs = list(authority_program('copper', stacking = list(class = 'primary_metal'),
    metal = list(type = 'copper'), rate = list(resolved = off)))))
con <- apply_operations(offspec, list(
  list(op = 'set_rate', authority = 'section_232', program = 'copper', rate = 0.50)))
check(isTRUE(con[['section_232']]$programs[[1]]$rate$resolved$has_232),
      'has_232 flips FALSE->TRUE when a dormant metal (copper) is turned on')

s <- apply_operations(rspecs, list(list(op = 'set_rate', authority = 'section_122', rate = 0.10)))
check(identical(s[['section_122']]$programs[[1]]$rate$default, 0.10),
      'set_rate s122 -> rate$default 0.10 (de-blobbed; calc gate value>0 turns it ON)')
check(is.null(s[['section_122']]$programs[[1]]$rate$resolved),
      's122 set_rate writes the structured rate$default layer, not a resolved blob (Plank 3)')

e <- apply_operations(rspecs, list(
  list(op = 'set_exempt', authority = 'section_232', program = 'steel', countries = c('1220', '2010'))))
check(identical(e[['section_232']]$programs[[1]]$rate$resolved$steel_exempt, c('1220', '2010')),
      'set_exempt 232/steel -> {Canada, Mexico}')

d <- apply_operations(rspecs, list(list(op = 'disable', authority = 'section_232')))
check(identical(d[['section_232']]$programs[[1]]$rate$resolved$steel_rate, 0),
      'disable 232 zeros steel_rate')
check(isFALSE(d[['section_232']]$programs[[1]]$rate$resolved$has_232),
      'disable 232 -> has_232 FALSE')

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
  'set_rate on ieepa (per-country tibble) errors — deferred follow-up')
expect_error(apply_operations(rspecs, list(list(op = 'disable', authority = 'ieepa_reciprocal'))),
  'disable ieepa errors — neither scope- nor rate-driven (deferred)')
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

cat(sprintf('\nALL %d SCENARIO_OPS ASSERTIONS PASSED\n', pass))
