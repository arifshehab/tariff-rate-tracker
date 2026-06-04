#!/usr/bin/env Rscript
# =============================================================================
# build_gather.R — gather step for the array build
# =============================================================================
#
# Run AFTER all array tasks (scripts/build_revision.R) have written their
# snapshot_<rev>.rds + ch99_/products_ caches. Does the cross-revision work the
# per-revision tasks deliberately skip, then the downstream:
#   1. deltas        — compare consecutive cached parses -> delta_<rev>.rds
#   2. products_raw  — data/processed/products_raw.csv from the latest revision
#                      (matches the serial loop's "last write wins")
#   3. assemble      — bind snapshots -> rate_timeseries.rds (+ parquet, metadata)
#   4. downstream    — daily series, weighted ETR, quality report
#
# Mirrors the serial build's post-loop + downstream so the array build's outputs
# match a serial build within parity tolerance.
#
# Usage:
#   Rscript scripts/build_gather.R [--unweighted] [--use-hts-dates]
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(jsonlite)
})
suppressMessages({
  source(here('src', '00_build_timeseries.R'))   # build helpers + assemble_timeseries()
  source(here('src', 'revisions.R'))
  source(here('src', 'policy_params.R'))
  source(here('src', '09_daily_series.R'))
  source(here('src', '08_weighted_etr.R'))
  source(here('src', 'quality_report.R'))
  source(here('src', 'build_import_weights.R'))
})

args <- commandArgs(trailingOnly = TRUE)
use_policy_dates <- !('--use-hts-dates' %in% args)
unweighted <- '--unweighted' %in% args
allow_partial <- '--allow-partial' %in% args   # opt out of the completeness gate
# Where the array tasks wrote their snapshots. Overridable (TARIFF_TS_DIR) so the
# gather can read an isolated candidate build without touching data/timeseries —
# mirrors scripts/build_revision.R. Downstream (daily/ETR) honors TARIFF_OUTPUT_DIR.
ts_dir_env <- Sys.getenv('TARIFF_TS_DIR')
output_dir <- if (nzchar(ts_dir_env)) ts_dir_env else here('data', 'timeseries')

init_logging(
  log_file = file.path(ensure_dir(here('output', 'logs')),
                       paste0('gather_', format(Sys.time(), '%Y%m%d_%H%M%S'), '.log')),
  level = 'info'
)

rev_dates <- load_revision_dates(use_policy_dates = use_policy_dates)
pp <- load_policy_params(use_policy_dates = use_policy_dates)

# Calculator-setup inputs — needed only to build synthetic future revisions
# (scheduled activations) below. Cheap to set up unconditionally; mirrors
# scripts/build_revision.R so the synthetic builds use the same inputs the
# array tasks did.
census_codes   <- read_csv(here('resources', 'census_codes.csv'),
                           col_types = cols(.default = col_character()))
countries      <- census_codes$Code
country_lookup <- build_country_lookup(here('resources', 'census_codes.csv'))
tpc_path       <- load_local_paths()$tpc_benchmark

# Ordered list of revisions that actually have a snapshot on disk.
all_revs <- rev_dates$revision
have_snap <- file.exists(file.path(output_dir, paste0('snapshot_', all_revs, '.rds')))
ordered <- rev_dates %>%
  filter(revision %in% all_revs[have_snap]) %>%
  arrange(effective_date) %>%
  pull(revision)
if (length(ordered) == 0) stop('No snapshots found in ', output_dir, ' — run the array build first.')
message('Gathering ', length(ordered), ' revisions: ', ordered[1], ' .. ', ordered[length(ordered)])

# Completeness gate (Finding 3): the array dispatches one task per revision that
# has a JSON archive (the same set list_revisions.R prints to size the array). If
# a task died, its snapshot is simply absent — and because the interval encoding
# stretches the prior revision over the gap, the assembled panel reads as policy
# stability rather than a missing revision. Reconcile the expected (available)
# set against what landed on disk and fail loud unless --allow-partial is set.
# When the array fully succeeded (the normal case), `missing_revs` is empty and
# this is a no-op — no stop(), identical assembly path.
available <- get_available_revisions_all_years(all_revs, here('data', 'hts_archives'))
expected_revs <- all_revs[all_revs %in% available]
missing_revs <- setdiff(expected_revs, ordered)
if (length(missing_revs) > 0 && !allow_partial) {
  stop('build_gather: ', length(missing_revs), ' of ', length(expected_revs),
       ' expected revision(s) have no snapshot in ', output_dir, ': ',
       paste(missing_revs, collapse = ', '),
       '. An array task likely failed; the assembled panel would silently ',
       'stretch a neighbouring revision over the gap. Re-run the failed ',
       'task(s), or pass --allow-partial to gather anyway.')
}
if (length(missing_revs) > 0) {
  warning('build_gather: gathering PARTIAL panel (--allow-partial) — ',
          length(missing_revs), ' expected revision(s) missing: ',
          paste(missing_revs, collapse = ', '))
}

# ---- 1. Deltas from cached parses (consecutive revisions) ----
message('Computing deltas from cached parses...')
prev_ch99 <- NULL; prev_products <- NULL
for (rev_id in ordered) {
  ch99_p <- file.path(output_dir, paste0('ch99_', rev_id, '.rds'))
  prod_p <- file.path(output_dir, paste0('products_', rev_id, '.rds'))
  if (!file.exists(ch99_p) || !file.exists(prod_p)) {
    warning('missing parse cache for ', rev_id, ' — skipping its delta'); next
  }
  ch99_data <- readRDS(ch99_p); products <- readRDS(prod_p)
  if (!is.null(prev_ch99)) {
    delta <- list(
      ch99 = compare_chapter99(prev_ch99, ch99_data),
      products = compare_products(prev_products, products)
    )
    saveRDS(delta, file.path(output_dir, paste0('delta_', rev_id, '.rds')))
  }
  prev_ch99 <- ch99_data; prev_products <- products
}

# ---- 2. products_raw.csv from the latest revision (serial "last write wins") ----
last_rev <- ordered[length(ordered)]
products_last <- readRDS(file.path(output_dir, paste0('products_', last_rev, '.rds')))
dir.create(here('data', 'processed'), recursive = TRUE, showWarnings = FALSE)
products_last %>%
  mutate(ch99_refs = vapply(ch99_refs, paste, FUN.VALUE = character(1), collapse = ';')) %>%
  select(hts10, base_rate, base_rate_raw, ch99_refs, n_ch99_refs, description) %>%
  write_csv(here('data', 'processed', 'products_raw.csv'))

# ---- 2b. Synthetic future revisions (scheduled activations) ----
# Build one synthetic revision per scheduled activation (tip archive stamped at
# the future date D + the activation's ops), writing snapshot_sched_*.rds into
# output_dir and appending {revision, effective_date} rows to rev_dates. Empty
# config => no-op (rev_dates unchanged, baseline byte-identical). Done here in
# the single-node gather (all archives available, tip known) rather than as
# extra array tasks. `last_rev` (the real tip from `ordered`) is pinned as
# last_revision so it tracks the last REAL HTS revision, not the synthetic one.
rev_dates <- build_scheduled_activations(
  rev_dates, pp, output_dir,
  country_lookup = country_lookup, countries = countries,
  census_codes = census_codes, archive_dir = here('data', 'hts_archives'),
  tpc_path = tpc_path)

# ---- 3. Assemble timeseries ----
result <- assemble_timeseries(output_dir, rev_dates, pp, scenario = 'baseline',
                              last_successful_rev = last_rev,
                              expected_revisions = expected_revs,
                              allow_partial = allow_partial)

# ---- 4. Downstream (mirrors 00_build_timeseries.R main block) ----
ts <- readRDS(result$timeseries_path)
if (unweighted) {
  tryCatch(run_daily_series(ts, imports = NULL, policy_params = pp),
           error = function(e) message('Daily series failed: ', conditionMessage(e)))
  tryCatch(run_quality_report(result$timeseries_path),
           error = function(e) message('Quality report failed: ', conditionMessage(e)))
} else {
  ensure_import_weights()
  imports <- load_import_weights()
  tryCatch(run_daily_series(ts, imports = imports, policy_params = pp),
           error = function(e) message('Daily series failed: ', conditionMessage(e)))
  tryCatch(run_weighted_etr(ts, policy_params = pp),
           error = function(e) message('Weighted ETR failed: ', conditionMessage(e)))
  tryCatch(run_quality_report(ts = ts, timeseries_path = result$timeseries_path),
           error = function(e) message('Quality report failed: ', conditionMessage(e)))
}

message('Gather complete: ', result$timeseries_path)
