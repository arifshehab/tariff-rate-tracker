# =============================================================================
# authority_adapter.R — JSON/param-object → AuthoritySpec re-packaging
# =============================================================================
#
# `build_authority_specs()` takes the bespoke per-authority Layer-B objects the
# parsers (03/04/05) already produce and re-packages them into a uniform
# `authority_spec_set` (see docs/authority_spec.md, src/authority_spec.R).
#
# PHASE 1 CONTRACT — lossless re-packaging, parity-safe by construction:
#   * The three bespoke objects that `calculate_rates_for_revision()` reads as
#     ad-hoc args — `s232_rates`, `ieepa_rates` (WITH its `universal_baseline`
#     attribute), `fentanyl_rates` — are embedded VERBATIM as attributes on the
#     authorities that own them (`raw_s232` on section_232, `raw_ieepa` on
#     ieepa_reciprocal, `raw_fentanyl` on ieepa_fentanyl).
#   * The calculator, when handed a spec set, pulls those identical R objects
#     back out and runs its unchanged body — so flag-on output is provably
#     identical to flag-off (ideally byte-identical: same objects).
#   * The normalized fields (`stacking.class`, `usmca_treatment`, `active`,
#     `country_scope`, `programs`) are populated here as a faithful scaffold for
#     Phase 2, but the calculator does NOT read them yet. Getting them slightly
#     wrong cannot break Phase 1 parity; Phase 2 makes them authoritative.
#   * `mfn` / `other` are constructed but inert (no raw payload; their data still
#     flows through the calculator's internal footnote-seeding / extraction).
#
# Source order: this file depends on src/authority_spec.R (constructors,
# validation, `%||%`) being sourced first, and on get_country_constants() from
# src/05_parse_policy_params.R for census-code scope population.
# =============================================================================

# Attribute names under which the raw objects are embedded. These are the
# contract read back by calculate_rates_for_revision() — keep in lockstep.
SPEC_RAW_ATTRS <- c(
  section_232      = 'raw_s232',
  ieepa_reciprocal = 'raw_ieepa',
  ieepa_fentanyl   = 'raw_fentanyl'
)

# ---- helpers ----------------------------------------------------------------
#
# Raw objects are embedded with plain `attr(spec, name) <- obj`, which stores the
# object verbatim — including its OWN attributes, so the `universal_baseline`
# attr on ieepa_rates survives the embed and the round-trip through RDS.

#' Pull the embedded legacy objects back out of a spec set. Used by the
#' calculator's transitional dual-signature path. Returns a named list with the
#' three ad-hoc args; a missing authority yields NULL for that slot.
specs_legacy_args <- function(specs) {
  list(
    ieepa_rates    = attr(specs[['ieepa_reciprocal']], 'raw_ieepa',    exact = TRUE),
    s232_rates     = attr(specs[['section_232']],      'raw_s232',     exact = TRUE),
    fentanyl_rates = attr(specs[['ieepa_fentanyl']],   'raw_fentanyl', exact = TRUE)
  )
}

#' Is the AuthoritySpec build path enabled? (TARIFF_USE_SPECS=1|true|yes)
#' Robust to the usual env-var spellings (as.logical("1") is NA, not TRUE).
use_specs_enabled <- function() {
  v <- tolower(trimws(Sys.getenv('TARIFF_USE_SPECS', '')))
  v %in% c('1', 'true', 'yes', 'on')
}

# ---- the adapter ------------------------------------------------------------

#' Re-package the bespoke per-authority parser outputs into an authority_spec_set.
#'
#' Signature mirrors calculate_rates_for_revision() so the build sites can call
#' it as a drop-in with the identical argument list.
#'
#' @param products,ch99_data,ieepa_rates,usmca parser outputs (Layer-B)
#' @param countries,revision_id,effective_date revision context
#' @param s232_rates,fentanyl_rates extracted rate objects (or NULL)
#' @param policy_params resolved policy params (or NULL → load_policy_params())
#' @return an `authority_spec_set` with raw objects embedded; validated.
build_authority_specs <- function(products, ch99_data, ieepa_rates, usmca,
                                  countries, revision_id, effective_date,
                                  s232_rates = NULL, fentanyl_rates = NULL,
                                  policy_params = NULL) {
  pp <- policy_params %||% load_policy_params()
  cc <- get_country_constants(pp)
  CTY_CHINA  <- cc$CTY_CHINA
  CTY_CANADA <- cc$CTY_CANADA
  CTY_MEXICO <- cc$CTY_MEXICO

  # IEEPA invalidation → ieepa programs' `active.until` (first inactive day,
  # exclusive — matches the calculator's `effective_date >= until` kill switch).
  # Mirror pp$IEEPA_INVALIDATION_DATE VERBATIM (incl. NULL when unset) so the
  # calc's `if (!is.null(until) && ...)` behaves identically — coercing NULL to
  # NA here would make the calc's `if (NA)` error (Phase 2d).
  ieepa_until <- pp$IEEPA_INVALIDATION_DATE

  # --- section_232 — the genuinely multi-program authority ------------------
  # Programs are a Phase-2 scaffold (rates/active derived authoritatively from
  # raw_s232 later); country exemptions live in the embedded raw object today.
  metal_prog <- function(id, type) authority_program(
    id = id, country_scope = list(include = 'all', exclude = list()),
    stacking = list(class = 'primary_metal'), metal = list(type = type, content = 'full'))
  full_prog <- function(id) authority_program(
    id = id, country_scope = list(include = 'all', exclude = list()),
    stacking = list(class = 'primary_full'), metal = list(type = 'none'))
  section_232 <- authority_spec(
    authority = 'section_232',
    stacking  = list(class = 'primary_metal', exceptions = list()),
    usmca_treatment = 'per_program',
    active = list(from = NA, until = NA),   # per-program heading gates (Phase 2c)
    programs = list(
      metal_prog('steel',    'steel'),
      metal_prog('aluminum', 'aluminum'),
      metal_prog('copper',   'copper'),
      full_prog('autos'),
      full_prog('mhd'),
      full_prog('wood'),
      full_prog('semiconductors')
    )
  )
  attr(section_232, 'raw_s232') <- s232_rates
  # Phase 2c: precompute the heading-program activation gates from the SAME
  # date-gated ch99 + authoritative s232 value the calc uses, so the calc reads
  # them off the spec instead of recomputing (compute_heading_gates is the single
  # source). Adapter owns the filter_active_ch99 gate (mirrors 06:738).
  if (!is.null(s232_rates)) {
    ch99_active <- filter_active_ch99(ch99_data, as.Date(effective_date))
    attr(section_232, 'heading_gates') <- compute_heading_gates(s232_rates, ch99_active)
  }

  # --- ieepa_reciprocal — blanket, country-level ----------------------------
  ieepa_reciprocal <- authority_spec(
    authority = 'ieepa_reciprocal',
    stacking  = list(class = 'content_split', exceptions = list()),
    usmca_treatment = 'eligible',
    active = list(from = NA, until = ieepa_until),
    programs = list(authority_program(
      id = 'reciprocal',
      product_scope = list(include = 'all'),
      country_scope = list(include = 'all'),   # universal_baseline default lives in raw
      rate = list(by_country = 'from_raw', default_unlisted_rate = 'from_raw')))
  )
  attr(ieepa_reciprocal, 'raw_ieepa') <- ieepa_rates

  # --- ieepa_fentanyl — content_split except China (additive), as data ------
  fentanyl_scope <- c(CTY_CHINA, CTY_CANADA, CTY_MEXICO)
  fentanyl_scope <- fentanyl_scope[!is.na(fentanyl_scope)]
  ieepa_fentanyl <- authority_spec(
    authority = 'ieepa_fentanyl',
    stacking  = list(class = 'content_split',
                     exceptions = setNames(list('additive'), CTY_CHINA %||% 'china')),
    usmca_treatment = 'exempt',
    active = list(from = NA, until = ieepa_until),
    programs = list(authority_program(
      id = 'fentanyl',
      product_scope = list(include = 'all'),
      country_scope = list(include = fentanyl_scope),
      rate = list(by_country = 'from_raw')))
  )
  attr(ieepa_fentanyl, 'raw_fentanyl') <- fentanyl_rates

  # --- section_301 — China gate as data (no raw embed; footnote-seeded) -----
  section_301 <- authority_spec(
    authority = 'section_301',
    stacking  = list(class = 'additive', exceptions = list()),
    usmca_treatment = 'none',
    active = list(from = NA, until = NA),
    programs = list(authority_program(
      id = 's301',
      product_scope = list(list_file = 'resources/s301_product_lists.csv'),
      country_scope = list(include = CTY_CHINA %||% '5700'),
      rate = list(by_product_tier = 'from_list')))
  )

  # --- section_201 — solar, Canada-exempt -----------------------------------
  section_201 <- authority_spec(
    authority = 'section_201',
    stacking  = list(class = 'additive', exceptions = list()),
    usmca_treatment = 'none',
    active = list(from = NA, until = NA),
    programs = list(authority_program(
      id = 's201',
      product_scope = list(list_file = 'resources/s201_solar_products.csv'),
      country_scope = list(include = 'all',
                           exclude = (CTY_CANADA %||% character(0)))))
  )

  # --- section_122 — non-discriminatory blanket -----------------------------
  section_122 <- authority_spec(
    authority = 'section_122',
    stacking  = list(class = 'content_split', exceptions = list()),
    usmca_treatment = 'eligible',
    active = list(from = NA, until = NA),
    programs = list(authority_program(
      id = 's122', product_scope = list(include = 'all'),
      country_scope = list(include = 'all')))
  )

  # --- mfn (base layer) + other (catch-all) — inert in Phase 1 --------------
  mfn <- authority_spec(
    authority = 'mfn',
    stacking  = list(class = 'additive', exceptions = list()),  # base layer; placeholder
    usmca_treatment = 'none',
    active = list(from = NA, until = NA),
    programs = list(authority_program(
      id = 'mfn', product_scope = list(include = 'all'),
      country_scope = list(include = 'all'),
      rate = list(default = 'from_products_base_rate')))
  )
  other <- authority_spec(
    authority = 'other',
    stacking  = list(class = 'additive', exceptions = list()),
    usmca_treatment = 'none',
    active = list(from = NA, until = NA),
    programs = list(authority_program(
      id = 'other', product_scope = list(include = 'all'),
      country_scope = list(include = 'all')))
  )

  specs <- authority_spec_set(
    section_232, section_301, ieepa_reciprocal, ieepa_fentanyl,
    section_122, section_201, mfn, other
  )

  # Record revision context as set-level metadata (not read in Phase 1; useful
  # for per-revision persistence in Phase 7 / debugging). Kept off the specs so
  # it never perturbs the embedded-object identity the parity gate relies on.
  attr(specs, 'revision_id')     <- revision_id
  attr(specs, 'effective_date')  <- effective_date

  validate_spec_set(specs)   # fail loud on any structural violation
  specs
}
