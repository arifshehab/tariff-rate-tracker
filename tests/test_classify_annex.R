# =============================================================================
# classify_s232_annex unit tests (Plank 4c — slice 1: shared classifier)
# =============================================================================
# Pure-logic checks for the shared §232 annex classifier in src/data_loaders.R
# (the single source of truth used by BOTH the calculator and the spec adapter).
# Pins the load-bearing behaviors that, if drifted, would red the parity gate:
#   - longest-prefix-first, first-match-wins,
#   - CSV match beats inference,
#   - chapter inference beats derivative inference (the 7616109030 arm-order case).
# No build data, no calculator. The extraction is a parity-neutral refactor.
#
# Usage: Rscript tests/test_classify_annex.R
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(tibble)
})
source(here('src', 'data_loaders.R'))

pass <- 0L
check <- function(cond, msg) {
  if (!isTRUE(cond)) stop('FAILED: ', msg, call. = FALSE)
  pass <<- pass + 1L; cat('  ok:', msg, '\n')
}

# Small annex prefix map mirroring load_annex_products() output shape: hts_prefix
# + an already-'annex_'-prefixed s232_annex column.
annex_map <- tibble(
  hts_prefix = c('8503',        # short catch-all
                 '85030045',    # longer, more specific -> must override 8503
                 '7301',        # chapter-73 product explicitly CSV-listed as 1b
                 '7616109090'), # sibling of the arm-order case, CSV-matched 1a
  s232_annex = c('annex_1b', 'annex_2', 'annex_1b', 'annex_1a')
)
# Derivative products drive the annex_1b inference fallback.
deriv <- tibble(hts_prefix = c('76161090',  # 7616109030 is ALSO a derivative...
                               '83021'))     # a non-metal-chapter derivative

cls <- function(x) classify_s232_annex(x, annex_map, deriv)

cat('--- longest-prefix-first, first-match-wins ---\n')
check(identical(cls('8503004500'), 'annex_2'),
      '8503004500 matches the longer 85030045 (annex_2), not 8503 (annex_1b)')
check(identical(cls('8503009000'), 'annex_1b'),
      '8503009000 matches only the short 8503 -> annex_1b')

cat('--- CSV match beats inference (CSV before chapter) ---\n')
check(identical(cls('7301000000'), 'annex_1b'),
      '7301000000 is chapter 73 but CSV-listed annex_1b -> CSV wins over chapter inference')

cat('--- chapter inference beats derivative inference (THE arm-order case) ---\n')
check(identical(cls('7616109030'), 'annex_1a'),
      '7616109030: chapter 76 (annex_1a) wins over derivative 76161090 (annex_1b)')
check(identical(cls('7616109090'), 'annex_1a'),
      '7616109090: CSV-matched annex_1a (sibling sanity)')

cat('--- pure inference ---\n')
check(identical(cls('7208000000'), 'annex_1a'),
      '7208000000: chapter 72, unmatched + non-derivative -> inferred annex_1a')
check(identical(cls('8302100000'), 'annex_1b'),
      '8302100000: chapter 83 (not a 1a-chapter), derivative 83021 -> inferred annex_1b')

cat('--- unclassified -> NA ---\n')
check(is.na(cls('6101000000')),
      '6101000000: chapter 61, unmatched + non-derivative -> NA')

cat('--- vector input preserves order + duplicates ---\n')
v <- classify_s232_annex(c('7208000000', '6101000000', '7208000000', '8503004500'),
                         annex_map, deriv)
check(identical(v, c('annex_1a', NA_character_, 'annex_1a', 'annex_2')),
      'vectorized: result aligned to input order, duplicates handled')

cat('--- empty annex_map -> inference only (fail-soft) ---\n')
check(identical(classify_s232_annex('7208000000', annex_map[0, ], deriv), 'annex_1a'),
      'empty map: chapter inference still applies')

cat('\nALL', pass, 'classify_s232_annex checks passed\n')
