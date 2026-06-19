# Quality report via the streaming snapshot path (no 70 GB rate_timeseries.rds).
# Mirrors run_daily_streaming.R: re-attaches the in-memory boundary-mint
# revisions (bnd_<date>) that load_revision_dates() omits, so snapshot ordering
# and anomaly sequencing match the intended timeline.

suppressMessages({
  library(here)
  library(tidyverse)
})
source(here('src', 'helpers.R'))
source(here('src', 'quality_report.R'))

rev_dates <- load_revision_dates()

snap_dir  <- here('data', 'timeseries')
bnd_snaps <- list.files(snap_dir, pattern = '^snapshot_bnd_\\d{4}-\\d{2}-\\d{2}\\.rds$')
bnd_revs  <- sub('^snapshot_(bnd_\\d{4}-\\d{2}-\\d{2})\\.rds$', '\\1', bnd_snaps)
bnd_dates <- as.Date(sub('^bnd_', '', bnd_revs))
missing   <- !(bnd_revs %in% rev_dates$revision)
if (any(missing)) {
  rev_dates <- bind_rows(rev_dates,
                         tibble(revision = bnd_revs[missing],
                                effective_date = bnd_dates[missing])) %>%
    arrange(effective_date)
  message('Re-attached ', sum(missing), ' boundary-mint revision(s).')
}

report <- run_quality_report(snapshot_dir = snap_dir, rev_dates = rev_dates)
