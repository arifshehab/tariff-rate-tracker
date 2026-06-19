# Targeted rebuild of the two pharma-active boundary snapshots after the §232
# pharma gate fix (06_calculate_rates.R: .pharma_hit no longer requires
# rate_232 > 0). Only bnd_2026-09-29 and bnd_2026-11-10 are affected (pharma is
# inactive before 2026-09-29). Both are future boundaries -> owner = tip archive
# 2026_rev_10 (confirmed via discover_boundaries for 2026-09-29).
#
# Writes to a STAGING dir; does NOT touch the live snapshots. A separate
# validation step compares staged vs live (only pharma rows may differ) before
# anything is promoted.

suppressMessages({
  library(here)
  library(tidyverse)
  library(jsonlite)
})
source(here('src', '00_build_timeseries.R'))   # defines build_revision_snapshot (+ sources 06 with the fix)

pp_build <- load_policy_params(use_policy_dates = TRUE)
census_codes_path <- here('resources', 'census_codes.csv')
census_codes <- read_csv(census_codes_path, col_types = cols(.default = col_character()))
countries <- census_codes$Code
country_lookup <- build_country_lookup(census_codes_path)

staging <- here('data', 'timeseries', 'staging_pharma_fix')
if (!dir.exists(staging)) dir.create(staging, recursive = TRUE)

targets <- tibble(
  rev_id = c('bnd_2026-09-29', 'bnd_2026-11-10'),
  eff    = as.Date(c('2026-09-29', '2026-11-10')),
  owner  = '2026_rev_10'
)

for (i in seq_len(nrow(targets))) {
  message('\n=== Rebuilding ', targets$rev_id[i], ' (owner ', targets$owner[i],
          ', stamped ', targets$eff[i], ') -> staging ===')
  build_revision_snapshot(
    rev_id = targets$rev_id[i], eff_date = targets$eff[i], tpc_date = NA,
    archive_rev_id = targets$owner[i],
    archive_dir = here('data', 'hts_archives'), output_dir = staging,
    country_lookup = country_lookup, countries = countries,
    census_codes = census_codes, pp_build = pp_build,
    stacking_method = 'mutual_exclusion', tpc_path = NULL
  )
}
message('\n=== Staged rebuild complete: ', staging, ' ===')
