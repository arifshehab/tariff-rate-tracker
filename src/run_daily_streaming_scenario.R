# Streaming weighted daily series for a SCENARIO snapshot dir.
# Usage: Rscript src/run_daily_streaming_scenario.R <scenario>
#   reads data/timeseries/<scenario>/snapshot_*.rds, ALWAYS decomposes the §232
#   rate into per-program columns first (data/timeseries/<scenario>/split_232/),
#   then streams the daily aggregates from the decomposed snapshots and writes
#   output/scenarios/<scenario>/daily/. Decomposing here (rather than as a
#   separate manual step) guarantees every scenario's daily_by_country_authority
#   carries the mean_232_*/etr_232_* per-program split — matching baseline.

suppressMessages({ library(here); library(tidyverse) })
source(here('src', 'helpers.R'))
source(here('src', '09_daily_series.R'))
source(here('src', 'decompose_232.R'))   # defines decompose_232() + membership data

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop('Usage: run_daily_streaming_scenario.R <scenario>')
scenario <- args[1]

pp        <- load_policy_params(use_policy_dates = TRUE, scenario = scenario)
rev_dates <- load_revision_dates()
imports   <- load_import_weights()

snap_dir  <- here('data', 'timeseries', scenario)
if (!dir.exists(snap_dir)) stop('Scenario snapshot dir not found: ', snap_dir)

# --- Always decompose §232 into per-program columns (split_232) ---
split_dir <- file.path(snap_dir, 'split_232')
if (!dir.exists(split_dir)) dir.create(split_dir, recursive = TRUE)
snaps <- list.files(snap_dir, pattern = '^snapshot_.*\\.rds$')
prog_cols <- c(paste0('rate_232_', PROGRAMS), 'rate_232_metals_unspecified', 'rate_232_other')
message('Decomposing §232 for ', length(snaps), ' scenario snapshots -> ', split_dir)
max_resid <- 0
for (f in snaps) {
  s <- decompose_232(readRDS(file.path(snap_dir, f)))
  max_resid <- max(max_resid, abs(max(rowSums(as.matrix(s[, prog_cols])) - coalesce(s$rate_232, 0))))
  saveRDS(s, file.path(split_dir, f))
}
message('  decompose reconcile (max diff): ', format(max_resid, scientific = TRUE))

# Re-attach boundary-mint revisions from the snapshot filenames (incl. the
# scenario's own turn-on, e.g. bnd_2026-08-01) — same reason as the baseline driver.
bnd_snaps <- list.files(split_dir, pattern = '^snapshot_bnd_\\d{4}-\\d{2}-\\d{2}\\.rds$')
bnd_revs  <- sub('^snapshot_(bnd_\\d{4}-\\d{2}-\\d{2})\\.rds$', '\\1', bnd_snaps)
bnd_dates <- as.Date(sub('^bnd_', '', bnd_revs))
missing   <- !(bnd_revs %in% rev_dates$revision)
if (any(missing)) {
  rev_dates <- bind_rows(rev_dates,
                         tibble(revision = bnd_revs[missing], effective_date = bnd_dates[missing])) %>%
    arrange(effective_date)
  message('Re-attached ', sum(missing), ' boundary-mint revision(s): ',
          paste(bnd_revs[missing], collapse = ', '))
}

cores <- suppressWarnings(as.integer(Sys.getenv('TARIFF_DAILY_CORES', unset = '2')))
if (is.na(cores) || cores < 1L) cores <- 1L

message('=== Scenario daily series: ', scenario, ' (cores=', cores, ') ===')
daily <- build_daily_aggregates_streaming(
  snapshot_dir  = split_dir,
  rev_dates     = rev_dates,
  imports       = imports,
  policy_params = pp,
  cores         = cores
)

out_dir <- here('output', 'scenarios', scenario, 'daily')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
save_daily_outputs(daily, out_dir = out_dir)
message('=== Scenario daily written to ', out_dir, ' ===')
