# External tariff-tracker comparison database

> Decision 2026-06-10: retire the manual TPC alignment table. Replace it with an
> automated comparison database of daily/periodic rate series from external
> trackers, refreshed by fetchers and compared against our `output/actual/daily/`
> series. Survey conducted 2026-06-10; all URLs below were fetched and verified
> that day. Fetchers MUST send a browser User-Agent (taxpolicycenter.org and
> several others 403 default R/python agents).

## The landscape (June 2026)

Two families of trackers exist. **Statutory** trackers (like ours) compute the
rate the law implies; **collections** trackers divide observed duties by import
value. Both are useful: statutory trackers validate our modeling, collections
benchmarks measure the compliance/timing wedge (which is `tariff-etr-adj`'s
subject).

### Statutory trackers

| Org | Series | Frequency | Access |
|---|---|---|---|
| **TPC** ("TPC Tariff Tracker", McClelland/Wong, rules engine v1.6) | Daily avg rate on 9 select goods; weekly avg-rate effect by tariff type; by-country snapshot | Republished per policy event (~weekly) | Datawrapper CSVs (below) |
| **Tax Foundation** (trump-tariffs-trade-war page) | Daily-dated event-step weighted-avg applied rate (29 steps, 11.7% as of Apr 2026); annual ETR 1821–2026; monthly revenue | Per policy event | Datawrapper CSVs (below) |
| **Global Trade Alert / SGEPT** | Every-working-day applied rate for ~235k country×HS8 flows incl. per-rate stacking formula | Continuous model; public file irregular | Static xlsx **stale (2025-12-23, pre-IEEPA-strikedown)**; live via their GTA MCP server; CC BY 4.0 |
| **Atlantic Council** | Country-level additional rates at ~7 discrete vintages; sector table; timeline | Per event | Flourish embed JSON (scrape; not strict JSON) |

### Collections benchmarks

| Org | Series | Frequency | Access |
|---|---|---|---|
| **Treasury Daily Treasury Statement** | Daily customs deposits (cash; ~1-month payment lag) | Daily, T+1 | Fiscal Data API, no key (below) |
| **Census trade API** | Monthly `CAL_DUT_MO` / `GEN_VAL_MO` by HS×country | Monthly ~T+35d | API, free key required |
| **PIIE revenue tracker** (Hufbauer/Zhang) | Monthly collections ETR + duties by BEC product and country | Monthly | Stable ZIP URL (below) |
| **Penn Wharton Budget Model** | Monthly collections ETR by country/product **plus a pre-substitution counterfactual rate** | Monthly | Excel per post; URL changes each month (needs post-resolver) |
| **CBP trade statistics** | Cumulative duties collected **by trade action/authority** | ~Monthly | HTML scrape only |

Event-list corroboration (no rate series): PIIE trade-war timeline (Google
Sheet), law-firm trackers (Reed Smith, ST&R, Husch Blackwell). No Fed source
maintains an ongoing average-rate series. Bloomberg/Conference Board/Fitch are
gated — skip.

## Verified fetch mechanics

### Datawrapper (TPC + Tax Foundation)

Chart data lives at `https://datawrapper.dwcdn.net/<id>/<version>/dataset.csv`.
**Old version paths serve frozen vintages** (verified: TPC `aO4iG` v1 ≠ v40),
and the bare `/<id>/dataset.csv` 404s, so the current version must be resolved
per fetch:

1. `GET https://datawrapper.dwcdn.net/<id>/` (browser UA) → tiny HTML with a
   meta refresh containing `url=https://datawrapper.dwcdn.net/<id>/<n>/`.
2. Parse `<n>`, then `GET .../<n>/dataset.csv`.
3. Store `<n>` as the vintage key; re-fetch daily but ingest only on version
   bump (the bump itself signals a republish/policy event).

Chart IDs:

| Source | ID | Content |
|---|---|---|
| TPC | `aO4iG` | Daily rate, 9 select goods, 2024-10-01 → 2026-12-31 incl. announced-policy projection (822 rows) |
| TPC | `MC81F` | Weekly avg-rate effect by tariff type (§301, §232 vehicles/materials, non-recip IEEPA, min/ctry-specific recip); columns sum to their overall increase path |
| TPC | `e1Iok` | Total rate by country (current snapshot, ~190 countries) |
| TPC | `UATS7` / `82415` / `9OJ4L` | Distribution table / revenue FY26-35 / type definitions (context only) |
| Tax Foundation | `hn0bW` | Daily-dated step series: date, rate, event label (TSV) |
| Tax Foundation | `2dFbJ` | Annual collections ETR 1821–2026 |
| Tax Foundation | `U7sme` | Monthly tariff revenue |

**TPC caveat:** the public endpoints do NOT include their overall daily series
or the daily by-trade-flow file we hold at `data/tpc/tariff_by_flow_day.csv` —
that came through the bilateral channel with McClelland/Wong and stays
private-channel for refreshes. The Datawrapper feeds are the automatable public
complement.

### Treasury DTS (daily customs deposits)

```
GET https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/dts/deposits_withdrawals_operating_cash?filter=record_date:eq:YYYY-MM-DD
```

Filter rows where `transaction_catg = "DHS - Customs Duties, Taxes, and Fees"`
(daily + MTD + FYTD columns; e.g. $394M on 2026-06-08). Public domain, no key.
Cash deposits lag accrual by roughly a month (periodic monthly statement), so
compare levels monthly and shapes with a lag, not day-by-day.

### PIIE revenue tracker

Stable URL, monthly refresh; poll with HEAD and ingest on `Last-Modified` change:

```
https://www.piie.com/sites/default/files/2025-08/tariff-revenue-tracker.zip
```

(2.2 MB; contains `jan25-mar26 data.xlsx`, raw HS6/country import files, HS→BEC
crosswalk, readme. © PIIE, attribution.)

### Census monthly (ground truth for collections)

```
GET https://api.census.gov/data/timeseries/intltrade/imports/hs?get=GEN_VAL_MO,CAL_DUT_MO&time=YYYY-MM&key=<free key>
```

Note the eval repo (`tariff-etr-adj`) already ingests this — reuse, don't
duplicate.

## Proposed design

```
data/comparison/                      # vintage-stamped raw pulls (committed, small)
  tpc/aO4iG_v<NN>.csv  MC81F_v<NN>.csv  e1Iok_v<NN>.csv
  taxfoundation/hn0bW_v<N>.tsv  2dFbJ_v<NN>.csv
  dts/customs_deposits.csv            # append-only daily
  piie/tariff-revenue-tracker_<Last-Modified>.zip (or extracted csv)
src/fetch_comparison_trackers.R       # all fetchers; browser UA; version/Last-Modified
                                      # change detection; idempotent (skip if vintage held)
src/compare_external_trackers.R       # tidy panel: date × source × series × value × vintage
                                      # + comparison report vs output/actual/daily/
output/comparison/                    # overlay CSVs + gap tables per source
```

Comparisons worth automating from day one:

1. **Headline daily ETR overlay** — ours vs Tax Foundation step series
   (forward-filled) vs TPC by-type sum (`MC81F`, weekly). Flag dates where the
   level gap moves by more than a threshold between vintages.
2. **Authority decomposition** — our `daily_by_authority` vs TPC `MC81F`
   columns (mapping: their "minimum/country-specific reciprocal" ↔ our IEEPA
   recip; their §232 split ↔ ours), and (scrape-permitting) CBP
   collections-by-action.
3. **By-country snapshot** — our `daily_by_country` on the TPC vintage date vs
   `e1Iok`; rank-correlation + top-10 gap table (replaces the old per-line TPC
   alignment table's country diagnostics).
4. **Product spot-checks** — our daily rates for TPC's 9 named goods vs
   `aO4iG` (their only public *daily* series; good high-frequency canary).
5. **Statutory-vs-collections wedge** — ours vs DTS (shape, monthly) and PIIE/
   Census (level, monthly); this overlaps `tariff-etr-adj`'s mandate, so keep
   the tracker side to ingestion + a simple overlay and leave η analysis there.

One-time (not pipeline): flow-level cross-validation against the GTA/SGEPT
public xlsx for a pre-strikedown date (closest methodological sibling — daily
statutory, HS8×country, explicit stacking formulas), and revisit ingestion if
they refresh the public file or once their MCP/API access is worth wiring.

## Relationship to existing TPC machinery

- `data/tpc/tariff_by_flow_day.csv` + `07_validate_tpc.R` + the diagnostics
  decomposition stay for *historical* validation at flow level (the private
  file remains far more granular than anything public).
- The per-revision TPC match-rate step in the build and the re-dating
  acceptance check move to the comparison database once items 1–3 above exist.
