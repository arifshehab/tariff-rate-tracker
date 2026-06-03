#!/usr/bin/env Rscript
# =============================================================================
# build_revision.R — build ONE revision's snapshot (the array-parallel unit)
# =============================================================================
#
# Wraps build_revision_snapshot() (src/00_build_timeseries.R) with the same
# setup build_full_timeseries() does, for exactly one revision. Writes only
# that revision's scoped artifacts (snapshot_<rev>.rds + ch99_/products_ caches
# + validation_<rev>.rds). Cross-revision work (deltas, products_raw.csv,
# timeseries assembly, downstream) is done by the gather step, not here.
#
# Usage:
#   Rscript scripts/build_revision.R <rev_id> [--use-hts-dates]
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(jsonlite)
})

# Sourcing 00 pulls in the full pipeline chain (logging/helpers/parallel/01-07)
# and defines build_revision_snapshot(). revisions.R + policy_params.R hold the
# setup helpers (load_revision_dates / load_policy_params / load_local_paths);
# source explicitly so we don't depend on transitive sourcing.
suppressMessages({
  source(here('src', '00_build_timeseries.R'))
  source(here('src', 'revisions.R'))
  source(here('src', 'policy_params.R'))
})

args <- commandArgs(trailingOnly = TRUE)
rev_id <- args[!grepl('^--', args)][1]
use_policy_dates <- !('--use-hts-dates' %in% args)
if (is.na(rev_id) || !nzchar(rev_id)) {
  stop('usage: Rscript scripts/build_revision.R <rev_id> [--use-hts-dates]', call. = FALSE)
}

archive_dir <- here('data', 'hts_archives')
# Output dir is overridable (TARIFF_TS_DIR) so a parallel build can write to an
# isolated directory and run concurrently with a serial build in data/timeseries.
ts_dir_env <- Sys.getenv('TARIFF_TS_DIR')
output_dir <- if (nzchar(ts_dir_env)) ts_dir_env else here('data', 'timeseries')
ensure_dir(output_dir)

init_logging(
  log_file = file.path(ensure_dir(here('output', 'logs')),
                       paste0('build_rev_', rev_id, '.log')),
  level = 'info'
)

rev_dates <- load_revision_dates(use_policy_dates = use_policy_dates)
ri <- rev_dates %>% filter(revision == rev_id)
if (nrow(ri) == 0) stop('unknown revision id: ', rev_id, call. = FALSE)

pp_build       <- load_policy_params(use_policy_dates = use_policy_dates)
census_codes   <- read_csv(here('resources', 'census_codes.csv'),
                           col_types = cols(.default = col_character()))
countries      <- census_codes$Code
country_lookup <- build_country_lookup(here('resources', 'census_codes.csv'))
tpc_path       <- load_local_paths()$tpc_benchmark

# Phase 2e: optional scenario operations — TARIFF_SCENARIO_OPS points at an RDS
# holding a list of ops (see src/scenario_ops.R). Unset => baseline (empty scenario).
ops <- NULL
ops_path <- Sys.getenv('TARIFF_SCENARIO_OPS')
if (nzchar(ops_path)) {
  if (!file.exists(ops_path)) stop('TARIFF_SCENARIO_OPS not found: ', ops_path, call. = FALSE)
  ops <- readRDS(ops_path)
  message('Loaded ', length(ops), ' scenario operation(s) from ', ops_path)
}

message('Building revision ', rev_id, ' (effective ', ri$effective_date, ') on ', Sys.info()[['nodename']])
res <- build_revision_snapshot(
  rev_id = rev_id, eff_date = ri$effective_date, tpc_date = ri$tpc_date,
  archive_dir = archive_dir, output_dir = output_dir,
  country_lookup = country_lookup, countries = countries,
  census_codes = census_codes, pp_build = pp_build,
  stacking_method = 'mutual_exclusion', tpc_path = tpc_path,
  operations = ops
)
message('OK: ', rev_id, ' -> ', res$snapshot_path, ' (', res$n_rates, ' rows)')
