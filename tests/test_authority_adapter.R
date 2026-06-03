# =============================================================================
# authority_adapter unit tests
# =============================================================================
# Pure-logic checks for src/authority_adapter.R — the Phase 1 lossless
# re-packaging. The crux of Phase 1 parity is: the raw per-authority objects
# (s232_rates / ieepa_rates / fentanyl_rates) round-trip through the spec set
# UNCHANGED — same R objects, with ieepa's `universal_baseline` attribute
# intact — both in memory and across saveRDS/readRDS. No model data needed.
#
# get_country_constants() / load_policy_params() (normally from
# 05_parse_policy_params.R) are stubbed so this runs without the parser
# pipeline. Usage: Rscript tests/test_authority_adapter.R
# =============================================================================

suppressPackageStartupMessages(library(here))
source(here('src', 'authority_spec.R'))

# --- stubs (stand in for 05_parse_policy_params.R; resolved at call time) -----
load_policy_params    <- function() list()
get_country_constants <- function(pp) list(CTY_CHINA = '5700', CTY_CANADA = '1220',
                                            CTY_MEXICO = '2010')

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

cat('\n--- lossless embed: identical R objects ---\n')
check(identical(attr(specs[['section_232']],      'raw_s232',     exact = TRUE), s232),
      'raw_s232 embedded verbatim on section_232')
check(identical(attr(specs[['ieepa_reciprocal']], 'raw_ieepa',    exact = TRUE), ieepa),
      'raw_ieepa embedded verbatim on ieepa_reciprocal')
check(identical(attr(specs[['ieepa_fentanyl']],   'raw_fentanyl', exact = TRUE), fent),
      'raw_fentanyl embedded verbatim on ieepa_fentanyl')
check(identical(attr(attr(specs[['ieepa_reciprocal']], 'raw_ieepa', exact = TRUE),
                     'universal_baseline', exact = TRUE), 0.10),
      'universal_baseline attribute survives the embed')

cat('\n--- specs_legacy_args round-trips to the calculator inputs ---\n')
legacy <- specs_legacy_args(specs)
check(identical(legacy$ieepa_rates, ieepa),    'specs_legacy_args$ieepa_rates == ieepa')
check(identical(legacy$s232_rates, s232),      'specs_legacy_args$s232_rates == s232')
check(identical(legacy$fentanyl_rates, fent),  'specs_legacy_args$fentanyl_rates == fent')

cat('\n--- normalized scaffold (not read in Phase 1, but should be faithful) ---\n')
check(identical(specs[['section_301']]$programs[[1]]$country_scope$include, '5700'),
      '301 China gate captured as country_scope data')
check(identical(specs[['section_201']]$programs[[1]]$country_scope$exclude, '1220'),
      '201 Canada exemption captured as country_scope exclude')
check(identical(specs[['section_232']]$stacking$class, 'primary_metal'),
      '232 authority stacking.class = primary_metal')

cat('\n--- serialization round-trip preserves embeds + nested attrs ---\n')
tmp <- tempfile(fileext = '.rds')
saveRDS(specs, tmp)
specs2 <- readRDS(tmp)
check(identical(attr(specs2[['section_232']], 'raw_s232', exact = TRUE), s232),
      'raw_s232 survives saveRDS/readRDS')
check(identical(attr(attr(specs2[['ieepa_reciprocal']], 'raw_ieepa', exact = TRUE),
                     'universal_baseline', exact = TRUE), 0.10),
      'universal_baseline survives saveRDS/readRDS')
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
