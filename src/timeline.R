# =============================================================================
# timeline.R — unified schedule-boundary splitter (Phase 3c)
# =============================================================================
# STATUS: standalone + unit-tested. NOT yet wired into the pipeline — the swap-in
# (replacing helpers.R get_expiry_split_points + the calc's per-gate handling)
# is the next step, gated by a baseline parity run.
#
# WHY. Today TWO mechanisms decide when a tariff switches on/off within a
# revision's date window, with OPPOSITE day conventions:
#
#   A. Downstream expiry splitter (helpers.R get_expiry_split_points /
#      apply_expiry_zeroing): splits a revision interval at SECTION_122 / SWISS
#      expiries using `> expiry` — i.e. the expiry date is the LAST LIVE day.
#      It only knows those two hardcoded expiries.
#   B. The calculator's effective_date gates (06): IEEPA invalidation uses
#      `>= until` — i.e. `until` is the FIRST DEAD day; annex activation /
#      annex_3 sunset / Ch99 offsets gate per-revision at the revision's date.
#
# Because A only knows two expiries, any OTHER mid-window switch (the annex
# turning on, a Ch99 offset activating between revision dates) is missed: the
# window carries one rate straight across the switch. And A vs B disagree by a
# day, so naively merging them shifts some tariffs.
#
# CANONICAL CONVENTION (this module). A `boundary` is the FIRST day of a NEW
# state — so (boundary - 1) is the last day of the prior state. Both legacy
# conventions map onto it cleanly:
#   - a "last live day" expiry  E  ->  boundary = E + 1   (first dead day)
#   - a "first dead day" until   U  ->  boundary = U        (already first dead)
# A split at boundary B inside a revision window (valid_from, valid_until] yields
# sub-intervals [.., B-1] and [B, ..]. This reproduces the existing
# get_expiry_split_points() behaviour after the +1 mapping (unit-tested), while
# ALSO admitting the boundaries mechanism A misses.
# =============================================================================

`%||%` <- function(x, y) if (is.null(x)) y else x

#' Canonical boundary from a "last live day" expiry (legacy `> expiry`).
boundary_from_expiry <- function(d) as.Date(d) + 1

#' Canonical boundary from a "first dead day" cutoff (legacy `>= until`).
boundary_from_until <- function(d) as.Date(d)

#' Collect every schedule boundary (FIRST-day-of-new-state convention) relevant
#' to a build. De-duplicated, sorted, NA/NULL dropped.
#'
#' Wired sources so far: IEEPA invalidation, SECTION_122 / SWISS expiries, and
#' spec active.from / active.until windows. The annex effective date, annex_3
#' sunset, and per-entry Ch99 effective_date_offsets are passed via `extra` until
#' the calc-side wiring step exposes them (TODO 3c-wiring) — kept out here rather
#' than guessing policy_params field names.
#'
#' @param policy_params load_policy_params() list, or NULL
#' @param specs         an authority_spec_set, or NULL
#' @param horizon       series horizon date, or NULL
#' @param extra         extra boundary dates (annex / Ch99 / scenario effective_from)
#' @return sorted unique Date vector of boundaries
collect_schedule_boundaries <- function(policy_params = NULL, specs = NULL,
                                        horizon = NULL, extra = NULL) {
  b <- as.Date(character())
  pp <- policy_params
  if (!is.null(pp)) {
    if (!is.null(pp$IEEPA_INVALIDATION_DATE)) {
      b <- c(b, boundary_from_until(pp$IEEPA_INVALIDATION_DATE))
    }
    if (!is.null(pp$SECTION_122) && isFALSE(pp$SECTION_122$finalized) &&
        !is.null(pp$SECTION_122$expiry_date)) {
      b <- c(b, boundary_from_expiry(pp$SECTION_122$expiry_date))
    }
    if (!is.null(pp$SWISS_FRAMEWORK) && isFALSE(pp$SWISS_FRAMEWORK$finalized) &&
        !is.null(pp$SWISS_FRAMEWORK$expiry_date)) {
      b <- c(b, boundary_from_expiry(pp$SWISS_FRAMEWORK$expiry_date))
    }
  }
  if (!is.null(specs)) {
    for (s in specs) {
      af <- s$active$from %||% NA          # first LIVE day == a boundary
      au <- s$active$until %||% NA          # first DEAD day == a boundary
      if (length(af) && !is.na(af)) b <- c(b, as.Date(af))
      if (length(au) && !is.na(au)) b <- c(b, boundary_from_until(au))
    }
  }
  if (!is.null(horizon)) b <- c(b, as.Date(horizon))
  if (!is.null(extra))   b <- c(b, as.Date(extra))
  b <- b[!is.na(b)]
  sort(unique(b))
}

#' Split points strictly inside a revision window: the dates at which a NEW
#' sub-interval STARTS. A boundary B splits (valid_from, valid_until] when
#' valid_from < B <= valid_until, giving [.., B-1] and [B, ..].
#'
#' Equivalence to the legacy splitter: legacy get_expiry_split_points() returns
#' E (= B - 1, the last live day) and 09 starts the next sub-interval at E + 1.
#' Feeding boundary_from_expiry(E) = E + 1 here returns that same start date, so
#' c(valid_from, timeline_split_points(...)) reproduces the legacy sub-interval
#' starts exactly (unit-tested) — and catches the extra boundaries too.
#'
#' @return sorted unique Date vector of sub-interval start days (empty == no split)
timeline_split_points <- function(valid_from, valid_until, boundaries) {
  vf <- as.Date(valid_from); vu <- as.Date(valid_until)
  b  <- as.Date(boundaries)
  sort(unique(b[!is.na(b) & b > vf & b <= vu]))
}

#' The parity-preserving boundary set for the downstream splitter swap: the legacy
#' expiry adjustments (SECTION_122 / SWISS) as canonical boundaries (last-live-day
#' E -> first-dead-day E+1). Depends on collect_expiry_adjustments() (helpers.R) at
#' call time. This is the bridge set; the mid-interval-activation fix adds the spec
#' active windows / annex / Ch99 offsets on top (via collect_schedule_boundaries).
expiry_boundaries <- function(policy_params) {
  adj <- collect_expiry_adjustments(policy_params)
  if (!length(adj)) return(as.Date(character()))
  e <- as.Date(vapply(adj, function(a) as.character(as.Date(a$expiry_date)), character(1)))
  sort(unique(boundary_from_expiry(e)))
}
