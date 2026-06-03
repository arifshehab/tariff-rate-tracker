#!/usr/bin/env Rscript
# =============================================================================
# list_revisions.R — print the revision ids the build would process, in order
# =============================================================================
#
# Same set build_full_timeseries() iterates: all revisions in revision_dates.csv
# that have a JSON archive available, in effective-date order. Used to size and
# index the Slurm array build (scripts/submit_build_array.sh). Prints ONE id per
# line to stdout (diagnostics go to stderr, so the list stays clean to capture).
#
# Usage:
#   Rscript scripts/list_revisions.R [--use-hts-dates]
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
})
suppressMessages({
  source(here('src', '00_build_timeseries.R'))
  source(here('src', 'revisions.R'))
})

use_policy_dates <- !('--use-hts-dates' %in% commandArgs(trailingOnly = TRUE))
rev_dates <- load_revision_dates(use_policy_dates = use_policy_dates)
all_revisions <- rev_dates$revision
available <- get_available_revisions_all_years(all_revisions, here('data', 'hts_archives'))
revs <- all_revisions[all_revisions %in% available]
cat(revs, sep = '\n')
cat('\n')
