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

cat('\n--- fail-loud: unsupported / invalid ops never silently no-op ---\n')
expect_error(apply_operations(specs, list(
  list(op = 'set_country_scope', authority = 'section_232',
       country_scope = list(include = 'all')))),
  'scope op on non-scope-driven authority (232) errors')
expect_error(apply_operations(specs, list(list(op = 'add_program', authority = 'section_232'))),
  'unsupported verb (add_program) errors')
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
    programs = list(authority_program('s122', rate = list(resolved = list(s122_rate = 0, has_s122 = FALSE)))))
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
check(identical(s[['section_122']]$programs[[1]]$rate$resolved$s122_rate, 0.10), 'set_rate s122 -> 0.10')
check(isTRUE(s[['section_122']]$programs[[1]]$rate$resolved$has_s122), 'has_s122 flips TRUE when s122 rate set > 0')

e <- apply_operations(rspecs, list(
  list(op = 'set_exempt', authority = 'section_232', program = 'steel', countries = c('1220', '2010'))))
check(identical(e[['section_232']]$programs[[1]]$rate$resolved$steel_exempt, c('1220', '2010')),
      'set_exempt 232/steel -> {Canada, Mexico}')

d <- apply_operations(rspecs, list(list(op = 'disable', authority = 'section_232')))
check(identical(d[['section_232']]$programs[[1]]$rate$resolved$steel_rate, 0),
      'disable 232 zeros steel_rate')
check(isFALSE(d[['section_232']]$programs[[1]]$rate$resolved$has_232),
      'disable 232 -> has_232 FALSE')

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

cat(sprintf('\nALL %d SCENARIO_OPS ASSERTIONS PASSED\n', pass))
