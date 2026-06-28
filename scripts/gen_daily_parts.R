#!/usr/bin/env Rscript
# Generate daily_part_<rev>.rds for every snapshot in TARIFF_TS_DIR.
# Reads each snapshot in turn (streaming, low peak RAM) and writes the
# weighted daily aggregate part alongside it.  Run before run_daily_streaming.R
# when the snapshot build was done without the array-task daily-part step.
#
# Usage:
#   TARIFF_TS_DIR=data/timeseries/updated_232_logic Rscript scripts/gen_daily_parts.R
suppressPackageStartupMessages({ library(here); library(tidyverse) })
suppressMessages({
  source(here('src', '00_build_timeseries.R'))
  source(here('src', 'revisions.R'))
  source(here('src', 'policy_params.R'))
  source(here('src', '09_daily_series.R'))
  source(here('src', 'build_import_weights.R'))
})

ts_dir <- Sys.getenv('TARIFF_TS_DIR', unset = here('data', 'timeseries'))
pp     <- load_policy_params()
rev_dates <- load_revision_dates()
ensure_import_weights()
imports <- load_import_weights()

rev_intervals <- build_snapshot_intervals_for_daily(ts_dir, rev_dates, pp)
message('Generating daily parts for ', nrow(rev_intervals), ' revisions in: ', ts_dir)

t0 <- proc.time()[['elapsed']]
for (i in seq_len(nrow(rev_intervals))) {
  row <- rev_intervals[i, ]
  snap_path <- file.path(ts_dir, paste0('snapshot_', row$revision, '.rds'))
  part_path <- file.path(ts_dir, paste0('daily_part_', row$revision, '.rds'))
  if (file.exists(part_path) &&
      file.info(part_path)$mtime >= file.info(snap_path)$mtime) {
    message('[', i, '/', nrow(rev_intervals), '] skip (up-to-date): ', row$revision)
    next
  }
  message('[', i, '/', nrow(rev_intervals), '] reading snapshot: ', row$revision)
  snapshot <- readRDS(snap_path)
  write_daily_part_for_snapshot(
    snapshot     = snapshot,
    revision     = row$revision,
    valid_from   = row$valid_from,
    valid_until  = row$valid_until,
    output_dir   = ts_dir,
    imports      = imports,
    policy_params = pp,
    stacking_method = 'mutual_exclusion'
  )
  rm(snapshot); gc(verbose = FALSE)
}
elapsed <- (proc.time()[['elapsed']] - t0) / 60
message(sprintf('Done: %d daily parts written in %.1f min', nrow(rev_intervals), elapsed))
