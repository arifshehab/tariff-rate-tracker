# =============================================================================
# authority_adapter unit tests
# =============================================================================
# Pure-logic checks for src/authority_adapter.R — the lossless re-packaging.
# The crux of parity (Phase 6b): the raw per-authority BLOB objects (s232_rates /
# ieepa_rates / fentanyl_rates) are parked VERBATIM in their owning program's
# rate$resolved slot and read back via *_from_specs() UNCHANGED — same R objects,
# with ieepa's `universal_baseline` attribute intact — both in memory and across
# saveRDS/readRDS. section_122 was DE-BLOBBED in Plank 3: its scalar blanket rate
# lives in the compositional rate$default layer (no rate$resolved). No model data.
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
compute_heading_gates <- function(specs, s232_rates) HEADING_GATES_SENTINEL  # S1b: (specs, s232_rates)
S122_SENTINEL <- list(s122_rate = 0.10, has_s122 = TRUE)   # Phase 6a
extract_section122_rates <- function(ch99_data) S122_SENTINEL
# S2 (blanket slice): the adapter calls is_232_exempt over `countries` to build the
# steel/aluminum by_country overlay. Census-only stub (the test data uses census codes).
is_232_exempt <- function(census_code, exempt_list) isTRUE(census_code %in% exempt_list)

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
check(identical(specs[['section_122']]$programs[[1]]$rate$default, S122_SENTINEL$s122_rate),
      's122 blanket rate structured into rate$default (Plank 3, de-blobbed)')
check(identical(specs[['section_122']]$programs[[1]]$rate$rate_type, 'surcharge'),
      's122 rate_type = surcharge (additive blanket duty)')
check(is.null(specs[['section_122']]$programs[[1]]$rate$resolved),
      's122 carries NO resolved blob (de-blobbed in Plank 3)')
check(identical(attr(ieepa_rates_from_specs(specs), 'universal_baseline', exact = TRUE), 0.10),
      'universal_baseline attribute rides along on the relocated ieepa payload')
check(is.null(attr(specs[['section_232']], 'raw_s232', exact = TRUE)),
      'no out-of-band raw_s232 attr remains (Phase 6b cleanup)')

cat('\n--- Plank 4a / S1a: blanket metal + auto base rates de-blobbed to rate$default ---\n')
s232_progs <- specs[['section_232']]$programs
.prog <- function(id) s232_progs[[which(vapply(s232_progs, function(p) identical(p$id, id), logical(1)))]]
check(identical(.prog('steel')$rate$default, 0.50),
      'steel base rate structured into rate$default (S1a, = s232$steel_rate)')
check(identical(.prog('aluminum')$rate$default, 0.50),
      'aluminum base rate structured into rate$default (S1a)')
check(identical(.prog('autos')$rate$default, 0),
      'autos base rate -> rate$default = 0 when s232$auto_rate absent (verbatim, incl. 0)')
check(identical(.prog('steel')$rate$rate_type, 'surcharge'),
      '232 program rate_type = surcharge (additive)')
check(identical(resolve_rate(.prog('steel')$rate)$value, 0.50),
      'calc-side read: resolve_rate(steel program) = 0.50 (the de-blobbed base)')
check(identical(resolve_rate(.prog('autos')$rate)$value, 0),
      'calc-side read: resolve_rate(autos program) = 0 (not NA) — baseline-safe')
check(identical(s232_rates_from_specs(specs), s232),
      'S1a coexistence: the residual resolved blob is still parked on programs[[1]] verbatim')

cat('\n--- Plank 4a / S2: steel/aluminum exempt + overrides + config -> rate$by_country ---\n')
check(identical(.prog('steel')$rate$by_country, stats::setNames(0, '1220')),
      'steel exempt list ({Canada}) de-blobbed to rate$by_country = {1220: 0} (S2)')
check(is.null(.prog('aluminum')$rate$by_country),
      'aluminum (no exempt/override/config) -> no by_country overlay (NULL)')
check(identical(resolve_rate(.prog('steel')$rate, product = NULL, country = '1220')$value, 0),
      'calc read: resolve_rate(steel, country=Canada) = 0 (exempt via by_country)')
check(identical(resolve_rate(.prog('steel')$rate, product = NULL, country = '5700')$value, 0.50),
      'calc read: resolve_rate(steel, country=China) = 0.50 (base; not in by_country)')

cat('\n--- Plank 4a / S1b: heading programs de-blobbed + dormant pharmaceuticals program ---\n')
prog_ids <- vapply(s232_progs, function(p) p$id, character(1))
check(length(s232_progs) == 8L && 'pharmaceuticals' %in% prog_ids,
      'section_232 has 8 programs incl. the dormant pharmaceuticals (S1b)')
check(identical(.prog('copper')$rate$default, 0) &&
      identical(.prog('mhd')$rate$default, 0) &&
      identical(.prog('wood')$rate$default, 0) &&
      identical(.prog('semiconductors')$rate$default, 0) &&
      identical(.prog('pharmaceuticals')$rate$default, 0),
      'copper/mhd/wood/semi/pharma base rates -> rate$default = 0 (absent in stub)')
check(identical(resolve_rate(.prog('pharmaceuticals')$rate)$value, 0),
      'calc-side read: resolve_rate(pharmaceuticals) = 0 (dormant, baseline-safe)')

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
check(identical(specs2[['section_122']]$programs[[1]]$rate$default, S122_SENTINEL$s122_rate),
      's122 program rate$default survives saveRDS/readRDS')
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
