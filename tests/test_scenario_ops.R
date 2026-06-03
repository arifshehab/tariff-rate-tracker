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

cat(sprintf('\nALL %d SCENARIO_OPS ASSERTIONS PASSED\n', pass))
