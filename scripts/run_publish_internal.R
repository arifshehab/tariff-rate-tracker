#!/usr/bin/env Rscript
# Standalone --publish-internal from a completed array+gather build (no --full
# rebuild). Mirrors the fresh actual/ vintage (per-interval snapshot parquets +
# daily + quality) to the shared Budget Lab tree and repoints `latest`.
# build_started_at = NULL: skip the staleness guard (panel was finalized by the
# array build + the weighted gather we just ran) and copy all output/actual files.
suppressPackageStartupMessages({ library(here); library(tidyverse); library(jsonlite) })
suppressMessages({
  source(here('src', '00_build_timeseries.R'))
  source(here('src', 'revisions.R'))
  source(here('src', 'policy_params.R'))
  source(here('src', 'output_paths.R'))
  source(here('src', 'publish_internal.R'))
})

publish_internal(
  build_started_at = NULL,
  update_latest    = TRUE,
  build_flags      = list(full = FALSE, core_only = TRUE, with_alternatives = FALSE,
                          array_build = TRUE,
                          note = 'theseus: pmax-wiring + 6 extreme-eta master fixes + revision re-dating')
)
