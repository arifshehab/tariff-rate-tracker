#!/usr/bin/env Rscript
# =============================================================================
# publish_vintage.R — publish ONE staged vintage to the model-data interface
# =============================================================================
# The single publish step of the reformed build. After the orchestrator has built
# the `actual` series + every scenario into an EXTERNAL staging tree (mirroring the
# repo layout: <staging>/data/timeseries[/<name>]/ and <staging>/output/{actual,
# scenarios/<name>}/), this hands that staging dir to write_build_output() as the
# `repo_root`, producing <model_data_root>/<vintage>/{actual, scenarios/<name>}/...
# in one call and (optionally) repointing `latest`. The repo is never read or written.
#
# Env (set by scripts/submit_build_array.sh):
#   TARIFF_STAGING          staging dir = repo_root for the publish (REQUIRED)
#   TARIFF_VINTAGE          vintage id YYYY-MM-DD-HH (REQUIRED; shared by all series)
#   TARIFF_MODEL_DATA_ROOT  interface root (optional; else local_paths.yaml default)
#   TARIFF_UPDATE_LATEST    '0' to publish additively without moving `latest`
# =============================================================================

suppressPackageStartupMessages(library(here))
source(here('src', 'write_output.R'))   # write_build_output + SHARED_ROOT_DEFAULT

staging <- Sys.getenv('TARIFF_STAGING', unset = '')
vintage <- Sys.getenv('TARIFF_VINTAGE', unset = '')
if (!nzchar(staging)) stop('TARIFF_STAGING not set', call. = FALSE)
if (!nzchar(vintage)) stop('TARIFF_VINTAGE not set', call. = FALSE)
if (!dir.exists(staging)) stop('staging dir does not exist: ', staging, call. = FALSE)

mdr <- Sys.getenv('TARIFF_MODEL_DATA_ROOT', unset = '')
shared_root <- if (nzchar(mdr)) mdr else SHARED_ROOT_DEFAULT
update_latest <- !identical(Sys.getenv('TARIFF_UPDATE_LATEST', '1'), '0')

message('Publishing vintage ', vintage, ' from staging ', staging, ' -> ', shared_root)
res <- write_build_output(
  shared_root       = shared_root,
  vintage           = vintage,
  repo_root         = staging,        # read the STAGED tree, not the repo
  build_started_at  = NULL,           # staging metadata just finalized; skip stale guard
  include_scenarios = TRUE,           # sweep every scenarios/<name> staged this run
  update_latest     = update_latest
)
message('Published vintage: ', res$vintage_dir,
        if (update_latest) paste0(' (latest -> ', res$vintage, ')') else ' (latest unchanged)')
