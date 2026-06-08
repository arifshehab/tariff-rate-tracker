# What the extreme etas say about the tariff-rate-tracker

June 2026. Cells are (country × HS2) over the training window (2025m5–2026m2),
from `data/processed/panel.rds`. "Statutory" = tracker `usmca_h2avg` rates
day-weighted to months; "collected" = Census IMDB calculated duties. Snapshot
evidence below is from `snapshot_rev_25.rds` (Oct 2025) and
`snapshot_2026_rev_2.rds` (Jan–Feb 2026). Dollar figures are the statutory-vs-
collected gap accumulated over the 10-month window.

A negative eta means collected > statutory (tracker likely **understates**);
an eta near 1 means collected ≈ 0 against positive statutory (tracker likely
**overstates**, or a legal exemption isn't modeled).

## Findings, ranked by money

### 1. Taiwan ch84 — semi-232 qualifying shares look far too low ($17.6B)
Taiwan machinery: statutory ETR 13.5% vs 0.8% collected on $139B of trade.
Snapshots charge `rate_232 = 23.8%` on 8471 computers — i.e. 25% × (1 − a
qualifying share of only ~5%) via `resources/semi_qualifying_shares.csv`.
Census collections imply the *de facto* qualifying (investment-exemption)
share is ~95%+. Companion issue: 8473 computer parts are charged the full 20%
reciprocal, but only 5 of the 8473 lines are on
`resources/ieepa_exempt_products.csv` — check 8473.21/29/30/50 against Annex
II / US Note 2(v)(iii). See also tariff-etr-eval
`docs/tracker_audits/s232_semi_calibration_2026-04-28.md`.

### 2. Country-specific EO layer appears to bypass the IEEPA exemption list (~$2.3B)
India pharma (3004): snapshots show `rate_ieepa_recip = 0.25` — exactly the
India EO (9903.01.84) with the Phase-2 component zeroed — even though **144
codes under 3004 are on the exempt list**. Same pattern on 9801 US-goods-
returned: Brazil 40%, India 25% (the EO rates), despite 47 ch98 codes on the
list. Hypothesis: in `06_calculate_rates.R`, the exemption zeroing is applied
to the Phase-1/2 reciprocal but the `country_eo` additions are summed on top
without passing through the same filter. Gaps: India ch30 $1.37B, Brazil ch98
$568M, India ch98 $293M.

### 3. The IEEPA exempt list is static → November 2025 ag carve-out applied retroactively (negative-eta cluster)
`ieepa_exempt_products.csv` contains coffee (0901: 35 codes), tea (0902),
flowers (0603: 39), cocoa (1801), palm oil (1511) — the Nov 14, 2025
agricultural Annex-II expansion. Because the list is not revision-dated, the
**October 2025** snapshot already shows reciprocal = 0 on Colombia coffee and
flowers, months before the carve-out existed. Result: statutory understated
Apr–Nov 2025, collected ≫ statutory, and the entire negative-eta cluster
(ch06 flowers η≈−4, ch09 coffee, ch18 cocoa, ch15 palm, ch08 fruit, ch21).
Fix: add an `effective_date` to the exemption list (or per-revision lists),
mirroring how floor exemptions are already revision-dated.

### 4. Gold bullion charged Canada/Mexico fentanyl ($0.9B)
7108 is on the IEEPA exempt list (reciprocal correctly 0) but **absent from
`resources/fentanyl_carveout_products.csv`**, so Canada gold carries the full
40% fentanyl rate (Oct 2025 and Jan 2026 snapshots alike). Census: 0.19%
collected on $6.6B — the Sept 2025 bullion clarification holds in practice.
Gaps: Canada ch71 $615M, Mexico ch71 $278M.

### 5. Ch97 (Berman) not on the exempt list ($0.3B+)
Zero 9701 codes on `ieepa_exempt_products.csv`; 15%-floor partners (e.g.
cty 4279) are charged 15% reciprocal on art vs ~0.4% collected. Informational
materials (Berman Amendment) should zero the IEEPA layers on ch97 (and check
ch49). Eval-side notes suggest this was identified before — verify the fix
made it into the tracker's current list and rebuilt snapshots.

### 6. Watch lines (ch91) missing from the product universe ($0.5B+)
High-volume Swiss watch HTS10s (9101.21.50xx, 9102.21.70xx, …) are **not in
the snapshots at all** — these are compound/specific-duty lines, suggesting
the rate parser drops lines it can't convert; the retained ch91 lines also
carry `base_rate = 0`. With the panel treating missing as 0, Switzerland ch91
shows 16.9% collected vs 1.8% statutory (η ≈ −2.3). Even without AVE-ing
specific duties, keeping the lines (base ≈ 0 or a rough AVE) would let the
15% Swiss-framework surcharge attach. Same missing-line issue seen on
8408.20.90.90 (Germany).

### 7. Canada crude USMCA eligibility (part of $1.6B ch27 gap)
2709.00.20.10 shows `usmca_eligible = FALSE` → full 10% energy-carve-out
fentanyl on a major crude line, while sibling 2709 lines are ~0 after USMCA
shares. In practice virtually all Canadian crude clears USMCA-compliant.
Verify the S/S+ `special`-field extraction for 2709.

### 8. AD/CVD — out of scope by design, but worth documenting
Vietnam ch85 collects $1.26B on lines the tracker correctly models at 0
(solar AD/CVD), and AD/CVD-heavy chapters (91, 06, 31) inflate collections
everywhere. Not a tracker bug; it *is* a reason the eta schedule has genuine
negative entries even after the fixes above.

## Caveat on "zero statutory" cells
The adj panel coalesces cells **missing from the snapshot** to rate 0, so the
zero-statutory-with-duties list mixes (a) modeled-zero (correct or item 2/3
above) with (b) missing lines (item 6) and (c) HTS10 concordance drift across
revisions. A tracker-side completeness check — Census HS10 universe vs
snapshot universe per revision, weighted by duties — would separate these
cheaply (`diagnostics.R` would be a natural home).
