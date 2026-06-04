# =============================================================================
# timeline swap-equivalence test (Phase 3c wiring)
# =============================================================================
# Proves the new 09 splitter path (timeline_split_points + expiry_boundaries)
# produces IDENTICAL sub-intervals to the legacy get_expiry_split_points path,
# across edge-case intervals — so routing 09 through the unified splitter changes
# no daily-series output. Sources helpers.R to use the REAL legacy function.
# Usage: Rscript tests/test_timeline_swap.R
# =============================================================================

suppressPackageStartupMessages({ library(here) })
source(here('src', 'helpers.R'))   # real get_expiry_split_points + collect_expiry_adjustments + timeline.R

pass <- 0L
check <- function(cond, msg) {
  if (!isTRUE(cond)) stop('FAILED: ', msg, call. = FALSE)
  pass <<- pass + 1L; cat('  ok:', msg, '\n')
}
d <- as.Date

# The OLD 09 sub-interval logic, verbatim (src/09_daily_series.R pre-3c).
legacy_subintervals <- function(vf, vu, pp) {
  splits <- get_expiry_split_points(vf, vu, pp)
  if (length(splits) == 0) return(list(starts = vf, ends = vu))
  list(starts = c(vf, splits + 1), ends = c(splits, vu))
}
# The NEW 09 sub-interval logic (post-3c), verbatim.
new_subintervals <- function(vf, vu, pp) {
  si <- timeline_split_points(vf, vu, expiry_boundaries(pp))
  if (length(si) == 0) return(list(starts = vf, ends = vu))
  list(starts = c(vf, si), ends = c(si - 1, vu))
}

pp <- list(
  SECTION_122     = list(finalized = FALSE, expiry_date = d('2025-07-04')),
  SWISS_FRAMEWORK = list(finalized = FALSE, expiry_date = d('2025-09-30'),
                         countries = c('5330', '5360'))
)

intervals <- list(
  c('2025-06-01', '2025-12-31'),   # both expiries strictly inside
  c('2025-01-01', '2025-06-30'),   # neither inside
  c('2025-07-04', '2025-12-31'),   # expiry exactly at valid_from
  c('2025-06-01', '2025-07-04'),   # expiry exactly at valid_until
  c('2025-08-01', '2025-09-30'),   # swiss expiry exactly at valid_until
  c('2025-10-01', '2025-12-31')    # after both expiries
)

cat('--- new 09 splitter == legacy get_expiry_split_points (sub-intervals) ---\n')
for (iv in intervals) {
  vf <- d(iv[1]); vu <- d(iv[2])
  L <- legacy_subintervals(vf, vu, pp); N <- new_subintervals(vf, vu, pp)
  check(identical(L$starts, N$starts) && identical(L$ends, N$ends),
        sprintf('[%s .. %s] identical sub-intervals (%d piece(s))', iv[1], iv[2], length(L$starts)))
}

cat('\n--- finalized expiries do not split (matches legacy) ---\n')
pp_final <- list(SECTION_122 = list(finalized = TRUE, expiry_date = d('2025-07-04')))
L <- legacy_subintervals(d('2025-06-01'), d('2025-12-31'), pp_final)
N <- new_subintervals(d('2025-06-01'), d('2025-12-31'), pp_final)
check(identical(L$starts, N$starts) && length(N$starts) == 1L,
      'finalized SECTION_122 -> no split, both paths agree')

cat(sprintf('\nALL %d TIMELINE-SWAP ASSERTIONS PASSED\n', pass))
