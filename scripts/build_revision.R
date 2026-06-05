#!/usr/bin/env Rscript
# =============================================================================
# build_revision.R — build ONE revision's snapshot (the array-parallel unit)
# =============================================================================
#
# Wraps build_revision_snapshot() (src/00_build_timeseries.R) with the same
# setup build_full_timeseries() does, for exactly one revision. Writes only
# that revision's scoped artifacts (snapshot_<rev>.rds + ch99_/products_ caches
# + validation_<rev>.rds). It also writes the revision-local daily aggregate part
# while the snapshot is in memory. Cross-revision work (deltas, products_raw.csv,
# interval validation, final output writes) is done by the gather step.
#
# Usage:
#   Rscript scripts/build_revision.R <rev_id> [--use-hts-dates] [--unweighted]
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
  source(here('src', '09_daily_series.R'))
  source(here('src', 'build_import_weights.R'))
})

args <- commandArgs(trailingOnly = TRUE)
rev_id <- args[!grepl('^--', args)][1]
use_policy_dates <- !('--use-hts-dates' %in% args)
unweighted <- '--unweighted' %in% args
if (is.na(rev_id) || !nzchar(rev_id)) {
  stop('usage: Rscript scripts/build_revision.R <rev_id> [--use-hts-dates] [--unweighted]', call. = FALSE)
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

# Precompute the per-revision daily aggregate part while the snapshot is still
# live in memory. Gather validates the part's mode + interval before using it,
# and falls back to streaming snapshots when parts are missing or stale.
if (!nzchar(Sys.getenv('TARIFF_SKIP_DAILY_PARTS'))) {
  available <- get_available_revisions_all_years(rev_dates$revision, archive_dir)
  available_dates <- rev_dates %>%
    filter(revision %in% available) %>%
    arrange(effective_date)
  idx <- match(rev_id, available_dates$revision)
  horizon_end <- as.Date(pp_build$SERIES_HORIZON_END %||% Sys.Date())
  valid_from <- as.Date(ri$effective_date)
  valid_until <- if (!is.na(idx) && idx < nrow(available_dates)) {
    as.Date(available_dates$effective_date[idx + 1L]) - 1
  } else {
    horizon_end
  }

  imports <- NULL
  if (!unweighted) {
    imports <- tryCatch(
      load_import_weights(),
      error = function(e) {
        message('  Daily part precompute skipped (weights unavailable): ',
                conditionMessage(e))
        NULL
      }
    )
  }

  if (unweighted || !is.null(imports)) {
    write_daily_part_for_snapshot(
      snapshot = res$rates,
      revision = rev_id,
      valid_from = valid_from,
      valid_until = valid_until,
      output_dir = output_dir,
      imports = imports,
      policy_params = pp_build,
      stacking_method = 'mutual_exclusion'
    )
  }
}
