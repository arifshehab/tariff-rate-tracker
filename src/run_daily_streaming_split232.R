# Daily series from the split_232 snapshots — same as run_daily_streaming.R but
# reads data/timeseries/split_232/ so daily_by_country_authority.csv gains the
# per-program mean_232_*/etr_232_* sub-columns. The split snapshots are a
# superset of the originals (identical rates + the rate_232_<sub> columns), so
# the other daily outputs are unchanged.

suppressMessages({
  library(here)
  library(tidyverse)
})
source(here('src', 'helpers.R'))
source(here('src', '09_daily_series.R'))

pp        <- load_policy_params()
rev_dates <- load_revision_dates()
imports   <- load_import_weights()

snap_dir  <- here('data', 'timeseries', 'split_232')
bnd_snaps <- list.files(snap_dir, pattern = '^snapshot_bnd_\\d{4}-\\d{2}-\\d{2}\\.rds$')
bnd_revs  <- sub('^snapshot_(bnd_\\d{4}-\\d{2}-\\d{2})\\.rds$', '\\1', bnd_snaps)
bnd_dates <- as.Date(sub('^bnd_', '', bnd_revs))
missing   <- !(bnd_revs %in% rev_dates$revision)
if (any(missing)) {
  rev_dates <- bind_rows(rev_dates,
                         tibble(revision = bnd_revs[missing], effective_date = bnd_dates[missing])) %>%
    arrange(effective_date)
  message('Re-attached ', sum(missing), ' boundary-mint revision(s).')
}

cores <- suppressWarnings(as.integer(Sys.getenv('TARIFF_DAILY_CORES', unset = '2')))
if (is.na(cores) || cores < 1L) cores <- 1L

message('=== Streaming weighted daily series from split_232 (cores=', cores, ') ===')
daily <- build_daily_aggregates_streaming(
  snapshot_dir  = snap_dir,
  rev_dates     = rev_dates,
  imports       = imports,
  policy_params = pp,
  cores         = cores
)

save_daily_outputs(daily)
message('=== Daily series (split_232) written ===')
