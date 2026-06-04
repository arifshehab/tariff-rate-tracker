# =============================================================================
# timeline real-data gate (Phase 3c)
# =============================================================================
# On the REAL policy params + REAL revision grid:
#   (1) PARITY GATE: the live 09 splitter (timeline_split_points fed
#       expiry_boundaries) yields IDENTICAL sub-intervals to the legacy
#       get_expiry_split_points path for every revision interval.
#   (2) FINDING: report any boundary the comprehensive collector adds beyond the
#       expiries that falls strictly mid-interval — surfaced for a deliberate
#       follow-up (these are what the legacy splitter misses).
# Usage: Rscript tests/test_timeline_realdata.R
# =============================================================================

suppressPackageStartupMessages({ library(here); library(dplyr); library(tidyr) })
source(here('src', 'helpers.R'))

pass <- 0L
check <- function(cond, msg) {
  if (!isTRUE(cond)) stop('FAILED: ', msg, call. = FALSE)
  pass <<- pass + 1L; cat('  ok:', msg, '\n')
}

pp <- load_policy_params()
rd <- load_revision_dates()
horizon <- as.Date('2026-12-31')

intervals <- rd %>%
  arrange(effective_date) %>%
  transmute(revision,
            valid_from  = as.Date(effective_date),
            valid_until = lead(as.Date(effective_date)) - 1) %>%
  mutate(valid_until = if_else(is.na(valid_until), horizon, valid_until))

exp_bounds  <- expiry_boundaries(pp)               # what the LIVE 09 splitter is fed
full_bounds <- collect_schedule_boundaries(pp)     # the comprehensive collector

# legacy 09 sub-intervals vs the live (timeline-based) ones
legacy_sub <- function(vf, vu) {
  s <- get_expiry_split_points(vf, vu, pp)
  if (!length(s)) list(starts = vf, ends = vu) else list(starts = c(vf, s + 1), ends = c(s, vu))
}
live_sub <- function(vf, vu) {
  si <- timeline_split_points(vf, vu, exp_bounds)
  if (!length(si)) list(starts = vf, ends = vu) else list(starts = c(vf, si), ends = c(si - 1, vu))
}

cat(sprintf('expiry boundaries (fed to live splitter): %s\n',
            if (length(exp_bounds)) paste(format(exp_bounds), collapse = ', ') else '(none)'))
cat(sprintf('checking %d real revision intervals...\n', nrow(intervals)))

mism <- 0L
for (i in seq_len(nrow(intervals))) {
  vf <- intervals$valid_from[i]; vu <- intervals$valid_until[i]
  L <- legacy_sub(vf, vu); N <- live_sub(vf, vu)
  if (!identical(L$starts, N$starts) || !identical(L$ends, N$ends)) {
    mism <- mism + 1L
    cat(sprintf('  MISMATCH %-12s [%s .. %s]\n', intervals$revision[i], vf, vu))
  }
}
check(mism == 0L, sprintf('live splitter (expiry boundaries) == legacy across all %d real intervals',
                          nrow(intervals)))

# --- FINDING: boundaries the comprehensive collector adds beyond expiries -----
extra <- full_bounds[!full_bounds %in% exp_bounds]
cat(sprintf('\nFINDING — comprehensive collector adds beyond expiries: %s\n',
            if (length(extra)) paste(format(extra), collapse = ', ') else '(none)'))
for (k in seq_along(extra)) {
  b <- extra[k]
  hit <- intervals %>% filter(valid_from < b, b <= valid_until)
  if (nrow(hit)) {
    for (j in seq_len(nrow(hit))) {
      cat(sprintf('  >> %s falls MID-INTERVAL in %s [%s .. %s] — legacy splitter misses it\n',
                  format(b), hit$revision[j], hit$valid_from[j], hit$valid_until[j]))
    }
  } else {
    cat(sprintf('  -- %s sits on a revision edge (no split)\n', format(b)))
  }
}

cat(sprintf('\nALL %d REAL-DATA TIMELINE ASSERTIONS PASSED\n', pass))
