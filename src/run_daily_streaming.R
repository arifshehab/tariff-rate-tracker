# Memory-safe daily series driver for low-RAM machines (e.g. 16 GB Macs).
#
# The orchestrator's assemble_timeseries() combine step materializes the full
# ~243M-row panel in RAM (~70 GB) and OOMs on 16 GB. The daily math never needs
# that monolith: build_daily_aggregates_streaming() reads ONE snapshot at a time
# (~1.2 GB peak) and produces identical weighted daily outputs. This driver runs
# that path directly over the already-built snapshots, then saves the daily CSVs.

suppressMessages({
  library(here)
  library(tidyverse)
})
source(here('src', 'helpers.R'))
source(here('src', '09_daily_series.R'))

pp        <- load_policy_params()
rev_dates <- load_revision_dates()
imports   <- load_import_weights()   # weighted (uses config/local_paths.yaml)

# The orchestrator mints synthetic `bnd_<date>` boundary revisions in-memory
# (discover_boundaries + build_boundary_mints) and writes a snapshot for each,
# but those rows are NOT persisted to config/revision_dates.csv. load_revision_dates()
# therefore omits them, and build_snapshot_intervals_for_daily() filters the
# boundary snapshots out (revision %in% rev_dates) — silently dropping e.g. the
# pharma 232 turn-on at bnd_2026-09-29. Re-attach one rev_dates row per on-disk
# boundary snapshot. The boundary date is the snapshot id suffix (bnd_<date>).
snap_dir   <- here('data', 'timeseries')
bnd_snaps  <- list.files(snap_dir, pattern = '^snapshot_bnd_\\d{4}-\\d{2}-\\d{2}\\.rds$')
bnd_revs   <- sub('^snapshot_(bnd_\\d{4}-\\d{2}-\\d{2})\\.rds$', '\\1', bnd_snaps)
bnd_dates  <- as.Date(sub('^bnd_', '', bnd_revs))
missing    <- !(bnd_revs %in% rev_dates$revision)
if (any(missing)) {
  add <- tibble(revision = bnd_revs[missing], effective_date = bnd_dates[missing])
  rev_dates <- bind_rows(rev_dates, add) %>% arrange(effective_date)
  message('Re-attached ', sum(missing), ' boundary-mint revision(s): ',
          paste(bnd_revs[missing], collapse = ', '))
}

cores <- suppressWarnings(as.integer(Sys.getenv('TARIFF_DAILY_CORES', unset = '2')))
if (is.na(cores) || cores < 1L) cores <- 1L

message('=== Streaming weighted daily series (cores=', cores, ') ===')
daily <- build_daily_aggregates_streaming(
  snapshot_dir   = here('data', 'timeseries'),
  rev_dates      = rev_dates,
  imports        = imports,
  policy_params  = pp,
  cores          = cores
)

save_daily_outputs(daily)
message('=== Daily series written ===')
