# Build the snapshots that a scenario CHANGES, into a scenario snapshot dir,
# reusing baseline snapshots for everything the scenario leaves untouched.
#
# Usage: Rscript src/build_scenario_snapshots.R <scenario> <date1> [<date2> ...]
#   <scenario>  config/scenarios/<scenario> (overlay deep-merged into pp)
#   <dateN>     boundary dates (YYYY-MM-DD) the scenario activates/changes;
#               each is built as bnd_<date> from the tip archive under scenario pp.
#
# Pre-step (done by the caller): copy all baseline data/timeseries/snapshot_*.rds
# into data/timeseries/<scenario>/. This driver then OVERWRITES / ADDS only the
# affected bnd_<date> snapshots there. Snapshots before the scenario's turn-on are
# identical to baseline, so the copies are correct as-is.

suppressMessages({ library(here); library(tidyverse); library(jsonlite) })
source(here('src', '00_build_timeseries.R'))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop('Usage: build_scenario_snapshots.R <scenario> <date1> [date2 ...]')
scenario <- args[1]
dates    <- as.Date(args[-1])
owner    <- '2026_rev_10'   # tip archive (latest real revision); all dates are future boundaries

pp_build <- load_policy_params(use_policy_dates = TRUE, scenario = scenario)
census_codes_path <- here('resources', 'census_codes.csv')
census_codes <- read_csv(census_codes_path, col_types = cols(.default = col_character()))
countries <- census_codes$Code
country_lookup <- build_country_lookup(census_codes_path)

out_dir <- here('data', 'timeseries', scenario)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

for (D in dates) {
  rev_id <- paste0('bnd_', as.character(as.Date(D, origin = '1970-01-01')))
  message('\n=== [', scenario, '] building ', rev_id, ' (owner ', owner, ') ===')
  build_revision_snapshot(
    rev_id = rev_id, eff_date = as.Date(D, origin = '1970-01-01'), tpc_date = NA,
    archive_rev_id = owner,
    archive_dir = here('data', 'hts_archives'), output_dir = out_dir,
    country_lookup = country_lookup, countries = countries,
    census_codes = census_codes, pp_build = pp_build,
    stacking_method = 'mutual_exclusion', tpc_path = NULL
  )
}
message('\n=== Scenario snapshots built into ', out_dir, ' ===')
