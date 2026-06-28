import json, csv, glob, os
from collections import Counter

# Paths are resolved relative to this script so it can be run from anywhere.
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
SNAP_DIR = os.path.join(REPO, 'data', 'statutory_rates', 'updated')
SRC_CSV  = os.path.join(REPO, 'data', 'statutory_rates', 'federal_register_sources.csv')
OUT      = os.path.join(SNAP_DIR, 'master_tariff_list.json')

# Base applies only if the most common rate covers MORE than this many countries.
# Exactly BASE_MIN does NOT get a base (must be > BASE_MIN).
BASE_MIN = 10

# Tariffs that use per-country-only logic (no modal base, ever).
COUNTRY_ONLY = {('ieepa', 'fentanyl')}

# The snapshot series opens at this window floor, but some tariffs were already in
# force earlier. These manual overrides restamp a tariff's first (floor) appearance
# with its true statutory effective date — used for BOTH the displayed date and the
# source lookup. Key (auth, name) targets the modal base; (auth, name, code) a
# specific country. Source resolution tries the overridden date, then the floor
# date, so only entries with a CSV row at the new date pick up a different link.
WINDOW_FLOOR = '2025-01-01'
START_OVERRIDE = {
    ('s232', 'steel'):             '2018-03-23',   # Proclamation 9705
    ('s232', 'aluminum'):          '2018-03-23',   # Proclamation 9704
    ('s232', 'aluminum', '4621'):  '2023-03-10',   # Russia 200%, Proclamation 10522
    ('s301', 'china_301', '5700'): '2024-09-27',   # China 301 four-year-review tranche
}


def emit_date(date, *key):
    """Restamp the floor date with the manual override, if one is set."""
    if date != WINDOW_FLOOR:
        return date
    return START_OVERRIDE.get(key, date)


def country_matches(cname, fr_name):
    """True if the country is named in the FR document title."""
    fr = fr_name.lower()
    cl = cname.lower()
    if cl in fr:
        return True
    for tok in cl.replace('(', ' ').replace(')', ' ').split():
        if len(tok) >= 4 and tok in fr:
            return True
    return False


def resolve(auth, name, date, code=None, cname=None):
    """Pick the source for one (auth, tariff, date). With a single CSV row that
    row wins. With several rows on the same date, disambiguate by matching the
    country against each row's fr_name; if that can't pin exactly one row, error."""
    rows = src.get((auth, name, date))
    if not rows:
        return None
    if len(rows) == 1:
        return rows[0]['link']
    if cname is None:
        raise SystemExit("ERROR: %d sources share key (%s, %s, %s) but the entry "
                         "has no country to disambiguate them." % (len(rows), auth, name, date))
    matches = [r for r in rows if country_matches(cname, r['name'])]
    # Hong Kong and Macau ride on the China action and are not named in the FR
    # title; fall back to matching China when their own name finds nothing.
    if not matches and cname.lower() in ('hong kong', 'macau'):
        matches = [r for r in rows if country_matches('China', r['name'])]
    if len(matches) == 1:
        return matches[0]['link']
    raise SystemExit("ERROR: cannot match a source for (%s, %s, %s) country '%s' (%s): "
                     "%d of %d fr_name rows match. Candidate fr_names: %s"
                     % (auth, name, date, cname, code, len(matches), len(rows),
                        [r['name'] for r in rows]))


def link_for(auth, name, edate, date, code=None, cname=None):
    """Source for an entry: try the (overridden) emit date, then the floor date."""
    return (resolve(auth, name, edate, code, cname)
            or resolve(auth, name, date, code, cname))

# 1. Sources keyed by (authority, tariff, effective_date) -> list of {name, link}.
#    The CSV has no country column, so when several rows share a key the resolver
#    matches the country against fr_name (see resolve / country_matches).
src = {}
with open(SRC_CSV) as f:
    for r in csv.DictReader(f):
        if not r.get('fr_link'):
            continue
        k = (r['authority'], r['tariff'], r['effective_date'])
        src.setdefault(k, []).append({'name': r['fr_name'], 'link': r['fr_link']})

# 2. Load every snapshot. Date comes from the in-file policy_effective_date.
#    On a tie of dates, revision files sort before bnd files (secondary key).
snaps = []
for fp in glob.glob(os.path.join(SNAP_DIR, 'tariff_rates_*.json')):
    data = json.load(open(fp))
    date = data['policy_effective_date']
    is_bnd = 1 if '_bnd_' in os.path.basename(fp) else 0
    snaps.append((date, is_bnd, fp, data))
snaps.sort(key=lambda x: (x[0], x[1]))
loaded = [(date, data) for date, _isbnd, _fp, data in snaps]


def countries(data):
    """Yield (census_code, country_obj), skipping the policy_effective_date key."""
    for code, c in data.items():
        if code == 'policy_effective_date':
            continue
        yield code, c


# 3. Establish a stable tariff ordering across all snapshots.
order = []
seen = set()
for _date, data in loaded:
    for _code, c in countries(data):
        for t in c.get('tariffs', []):
            key = (t['tariff_authority'], t['tariff_name'])
            if key not in seen:
                seen.add(key)
                order.append(key)

result = []
missing = []
for auth, name in order:
    eff = []
    prev_base = None
    tracked = {}
    country_only = (auth, name) in COUNTRY_ONLY

    for date, data in loaded:
        rates = {}
        cnames = {}
        for code, c in countries(data):
            for t in c.get('tariffs', []):
                if (t['tariff_authority'], t['tariff_name']) == (auth, name):
                    rates[code] = t['tariff_rate']
                    cnames[code] = c['name']
        if not rates:
            continue

        # Decide whether this snapshot gets a modal base or full enumeration.
        if country_only:
            use_base = False
        else:
            counts = Counter(rates.values())
            top = counts.most_common()
            top_count = top[0][1]
            is_tie = len(top) > 1 and top[0][1] == top[1][1]
            thin = top_count <= BASE_MIN   # base needs > BASE_MIN countries
            use_base = not (is_tie or thin)

        if not use_base:
            # No base: every country is listed explicitly (deduped over time).
            # Any country not yet tracked is emitted now, so a lingering previous
            # base is overridden by explicit per-country rows. prev_base is left
            # unchanged. Already-tracked countries emit only on a rate change.
            for code, r in rates.items():
                if code in tracked and r == tracked[code]:
                    continue
                edate = emit_date(date, auth, name, code)
                ent = {'country_name': cnames[code], 'census_code': code,
                       'adjust_date': edate, 'adjust_rate': r}
                link = link_for(auth, name, edate, date, code, cnames[code])
                if link:
                    ent['source'] = link
                else:
                    missing.append(('country', name, code, cnames[code], edate, r))
                eff.append(ent)
                tracked[code] = r
        else:
            base = top[0][0]
            if base != prev_base:
                edate = emit_date(date, auth, name)
                ent = {'base_date': edate, 'base_rate': base}
                link = link_for(auth, name, edate, date)
                if link:
                    ent['source'] = link
                else:
                    missing.append(('base', name, edate, base))
                eff.append(ent)
                prev_base = base
            for code, r in rates.items():
                emit = False
                if code in tracked:
                    if r != tracked[code]:
                        emit = True
                elif r != base:
                    emit = True
                if emit:
                    edate = emit_date(date, auth, name, code)
                    ent = {'country_name': cnames[code], 'census_code': code,
                           'adjust_date': edate, 'adjust_rate': r}
                    link = link_for(auth, name, edate, date, code, cnames[code])
                    if link:
                        ent['source'] = link
                    else:
                        missing.append(('country', name, code, cnames[code], edate, r))
                    eff.append(ent)
                    tracked[code] = r

    result.append({'tariff_authority': auth, 'tariff_name': name, 'effective_date': eff})

json.dump(result, open(OUT, 'w'), indent=2)

tot = sum(len(t['effective_date']) for t in result)
carried = tot - len(missing)
print('output: %s' % OUT)
print('entries: %d  | sources carried over: %d  | needing source (new/changed): %d'
      % (tot, carried, len(missing)))
print('---- entries needing a source ----')
for m in missing:
    print('  ', *m)
