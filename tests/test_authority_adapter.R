# =============================================================================
# authority_adapter unit tests
# =============================================================================
# Pure-logic checks for src/authority_adapter.R — the lossless re-packaging.
# The crux of parity (Phase 6b): the raw per-authority objects (s232_rates /
# ieepa_rates / fentanyl_rates / s122) are parked VERBATIM in their owning
# program's rate$resolved slot and read back via *_from_specs() UNCHANGED —
# same R objects, with ieepa's `universal_baseline` attribute intact — both in
# memory and across saveRDS/readRDS. No model data needed.
#
# get_country_constants() / load_policy_params() (normally from
# 05_parse_policy_params.R) are stubbed so this runs without the parser
# pipeline. Usage: Rscript tests/test_authority_adapter.R
# =============================================================================

suppressPackageStartupMessages(library(here))
source(here('src', 'authority_spec.R'))

# --- stubs (stand in for 05_parse_policy_params.R / rate_schema.R / 06; resolved
#     at call time in the global env) ----------------------------------------
load_policy_params    <- function() list()
get_country_constants <- function(pp) list(CTY_CHINA = '5700', CTY_CANADA = '1220',
                                            CTY_MEXICO = '2010')
filter_active_ch99    <- function(ch99_data, effective_date) ch99_data
HEADING_GATES_SENTINEL <- list(autos_passenger = TRUE, copper = FALSE)
compute_heading_gates <- function(s232_rates) HEADING_GATES_SENTINEL   # Phase 6c: pure fn of s232_rates
S122_SENTINEL <- list(s122_rate = 0.10, has_s122 = TRUE)   # Phase 6a
extract_section122_rates <- function(ch99_data) S122_SENTINEL

source(here('src', 'authority_adapter.R'))

pass <- 0L
check <- function(cond, msg) {
  if (!isTRUE(cond)) stop('FAILED: ', msg, call. = FALSE)
  pass <<- pass + 1L; cat('  ok:', msg, '\n')
}

# --- synthetic raw objects (contents opaque to the adapter; only identity matters)
ieepa <- data.frame(country = c('5700', '4280'), rate = c(0.20, 0.10),
                    stringsAsFactors = FALSE)
attr(ieepa, 'universal_baseline') <- 0.10        # must survive the embed + RDS
s232  <- list(has_232 = TRUE, steel_rate = 0.50, aluminum_rate = 0.50,
              steel_exempt = c('1220'))
fent  <- data.frame(country = c('5700', '1220', '2010'), rate = c(0.20, 0.25, 0.25),
                    stringsAsFactors = FALSE)

cat('--- build_authority_specs (no IEEPA invalidation) ---\n')
specs <- build_authority_specs(
  products = data.frame(), ch99_data = data.frame(),
  ieepa_rates = ieepa, usmca = data.frame(),
  countries = c('5700', '1220', '2010'),
  revision_id = 'rev_test', effective_date = as.Date('2025-06-01'),
  s232_rates = s232, fentanyl_rates = fent, policy_params = list()
)

check(is_authority_spec_set(specs), 'returns an authority_spec_set')
check(setequal(names(specs),
               c('section_232', 'section_301', 'ieepa_reciprocal', 'ieepa_fentanyl',
                 'section_122', 'section_201', 'mfn', 'other')),
      'all eight authorities present')
check(isTRUE(validate_spec_set(specs)), 'validates (fail-loud passed inside)')

cat('\n--- lossless relocation: identical R objects in programs[[1]]$rate$resolved ---\n')
check(identical(s232_rates_from_specs(specs), s232),
      's232 21-field list reachable via s232_rates_from_specs (parked on programs[[1]])')
check(identical(ieepa_rates_from_specs(specs), ieepa),
      'ieepa tibble reachable via ieepa_rates_from_specs')
check(identical(fentanyl_rates_from_specs(specs), fent),
      'fentanyl tibble reachable via fentanyl_rates_from_specs')
check(identical(s122_rates_from_specs(specs), S122_SENTINEL),
      's122 list reachable via s122_rates_from_specs')
check(identical(specs[['section_122']]$programs[[1]]$rate$resolved, S122_SENTINEL),
      's122 payload stored verbatim in programs[[1]]$rate$resolved')
check(identical(attr(ieepa_rates_from_specs(specs), 'universal_baseline', exact = TRUE), 0.10),
      'universal_baseline attribute rides along on the relocated ieepa payload')
check(is.null(attr(specs[['section_232']], 'raw_s232', exact = TRUE)),
      'no out-of-band raw_s232 attr remains (Phase 6b cleanup)')

cat('\n--- normalized scaffold (not read in Phase 1, but should be faithful) ---\n')
check(identical(specs[['section_301']]$programs[[1]]$country_scope$include, '5700'),
      '301 China gate captured as country_scope data')
check(identical(specs[['section_201']]$programs[[1]]$country_scope$exclude, '1220'),
      '201 Canada exemption captured as country_scope exclude')
check(identical(specs[['section_232']]$stacking$class, 'primary_metal'),
      '232 authority stacking.class = primary_metal')
check(identical(attr(specs[['section_232']], 'heading_gates', exact = TRUE),
                HEADING_GATES_SENTINEL),
      '232 heading_gates precomputed onto the spec (Phase 2c)')

cat('\n--- serialization round-trip preserves relocated payloads + nested attrs ---\n')
tmp <- tempfile(fileext = '.rds')
saveRDS(specs, tmp)
specs2 <- readRDS(tmp)
check(identical(s232_rates_from_specs(specs2), s232),
      's232 program rate$resolved survives saveRDS/readRDS')
check(identical(specs2[['section_122']]$programs[[1]]$rate$resolved, S122_SENTINEL),
      's122 program rate$resolved survives saveRDS/readRDS')
check(identical(attr(ieepa_rates_from_specs(specs2),
                     'universal_baseline', exact = TRUE), 0.10),
      'universal_baseline survives saveRDS/readRDS (rides along on relocated payload)')
check(isTRUE(validate_spec_set(specs2)), 'round-tripped set still validates')

cat('\n--- IEEPA invalidation maps to active.until on both ieepa specs ---\n')
specs_inv <- build_authority_specs(
  products = data.frame(), ch99_data = data.frame(),
  ieepa_rates = ieepa, usmca = data.frame(),
  countries = '5700', revision_id = 'rev_inv', effective_date = as.Date('2026-03-01'),
  s232_rates = s232, fentanyl_rates = fent,
  policy_params = list(IEEPA_INVALIDATION_DATE = as.Date('2026-02-24'))
)
check(identical(specs_inv[['ieepa_reciprocal']]$active$until, as.Date('2026-02-24')),
      'reciprocal active.until = invalidation date')
check(identical(specs_inv[['ieepa_fentanyl']]$active$until, as.Date('2026-02-24')),
      'fentanyl active.until = invalidation date')

cat(sprintf('\nALL %d AUTHORITY_ADAPTER ASSERTIONS PASSED\n', pass))
