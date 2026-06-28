import json, csv, glob, os
from collections import Counter

# 1. Capture existing sources keyed by entry identity
old=json.load(open('master_tariff_list.json'))
src={}
for t in old:
    nm=t['tariff_name']
    for e in t['effective_date']:
        if 'base_date' in e:
            k=(nm,'base',e['base_date'],e['base_rate'])
        else:
            k=(nm,'ctry',e['census_code'],e['adjust_date'],e['adjust_rate'])
        if 'source' in e: src[k]=e['source']

# 2. Regenerate from source JSONs
rev_date={}
with open('../../config/revision_dates.csv') as f:
    for r in csv.DictReader(f):
        ped=r['policy_effective_date']
        rev_date[r['revision']] = ped if ped and ped!='NA' else r['effective_date']
def fpath(rev):
    if rev=='basic': return 'tariff_rates_basic.json'
    if rev=='2026_basic': return 'tariff_rates_2026_basic.json'
    if rev.startswith('2026_rev_'): return 'tariff_rates_2026_%s.json'%rev.split('2026_')[1]
    return 'tariff_rates_%s.json'%rev
snaps=[]
for rev,date in rev_date.items():
    fp=fpath(rev)
    if os.path.exists(fp): snaps.append((date,0,fp))
for fp in glob.glob('tariff_rates_bnd_*.json'):
    date=fp.replace('tariff_rates_bnd_','').replace('.json','')
    snaps.append((date,1,fp))
snaps.sort(key=lambda x:(x[0],x[1]))
loaded=[(date,json.load(open(fp))) for date,isbnd,fp in snaps]

order=[]; seen=set()
for date,data in loaded:
    for c in data.values():
        for t in c.get('tariffs',[]):
            key=(t['tariff_authority'],t['tariff_name'])
            if key not in seen: seen.add(key); order.append(key)

# Tariffs that use per-country-only logic (no modal base)
COUNTRY_ONLY = {('ieepa','fentanyl')}

result=[]; missing=[]
for auth,name in order:
    eff=[]; prev_base=None; tracked={}
    country_only = (auth,name) in COUNTRY_ONLY

    for date,data in loaded:
        rates={}; cnames={}
        for code,c in data.items():
            for t in c.get('tariffs',[]):
                if (t['tariff_authority'],t['tariff_name'])==(auth,name):
                    rates[code]=t['tariff_rate']; cnames[code]=c['name']
        if not rates: continue

        if country_only:
            # Emit a country entry whenever a country's rate changes; no base entry
            for code,r in rates.items():
                if code not in tracked or r!=tracked[code]:
                    ent={'country_name':cnames[code],'census_code':code,'adjust_date':date,'adjust_rate':r}
                    k=(name,'ctry',code,date,r)
                    if k in src: ent['source']=src[k]
                    else: missing.append(('country',name,code,cnames[code],date,r))
                    eff.append(ent); tracked[code]=r
        else:
            base=Counter(rates.values()).most_common(1)[0][0]
            if base!=prev_base:
                ent={'base_date':date,'base_rate':base}
                k=(name,'base',date,base)
                if k in src: ent['source']=src[k]
                else: missing.append(('base',name,date,base))
                eff.append(ent); prev_base=base
            for code,r in rates.items():
                emit=False
                if code in tracked:
                    if r!=tracked[code]: emit=True
                elif r!=base: emit=True
                if emit:
                    ent={'country_name':cnames[code],'census_code':code,'adjust_date':date,'adjust_rate':r}
                    k=(name,'ctry',code,date,r)
                    if k in src: ent['source']=src[k]
                    else: missing.append(('country',name,code,cnames[code],date,r))
                    eff.append(ent); tracked[code]=r

    result.append({'tariff_authority':auth,'tariff_name':name,'effective_date':eff})

json.dump(result,open('master_tariff_list.json','w'),indent=2)

tot=sum(len(t['effective_date']) for t in result)
carried=tot-len(missing)
print('entries: %d  | sources carried over: %d  | needing source (new/changed): %d'%(tot,carried,len(missing)))
print('---- entries needing a source ----')
for m in missing:
    print('  ',*m)
