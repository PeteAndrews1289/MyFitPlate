#!/usr/bin/env python3
"""Project public API response fields into replay.json for the actual Swift parser/ranker.
No network or account access. This keeps the full raw gzip evidence in its source directory.
"""
import argparse,gzip,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
USDA_FIELDS={'fdcId','description','dataType','brandName','brandOwner','gtinUpc','modifiedDate','publishedDate','servingSize','servingSizeUnit','householdServingFullText','foodNutrients'}
OFF_FIELDS={'code','product_name','brands','serving_size','serving_quantity','last_modified_t','nutriments'}
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('capture_directory',type=Path)
p.add_argument('--corpus',type=Path,default=ROOT/'docs/wave-4-assets/search-qualification/corpus.json')
a=p.parse_args()
corpus={x['id']:x for x in json.loads(a.corpus.read_text())['queries']}
records=[json.loads(s) for s in (a.capture_directory/'requests.jsonl').read_text().splitlines()]
replay=[]
for r in records:
 q=corpus[r['query_id']]
 item={'id':q['id'],'query':q['query'],'category':q['category'],'targetBrand':q['target_brand'],'targetWords':q['target_words'],
       'provider':r['provider'],'variant':r['variant'],'status':r.get('http_status'),'elapsedMs':r['elapsed_ms'],'payload':None}
 if r.get('capture'):
  relative=Path(r['capture'])
  if relative.is_absolute() or '..' in relative.parts: raise SystemExit('Unexpected capture path')
  with gzip.open(a.capture_directory/relative,'rb') as f: payload=json.load(f)
  if r['provider']=='usda':
   projected=[]
   for food in payload.get('foods',[]):
    food={k:v for k,v in food.items() if k in USDA_FIELDS}
    food['foodNutrients']=[{k:v for k,v in n.items() if k in ['nutrientId','nutrientNumber','value','unitName']} for n in food.get('foodNutrients',[])]
    projected.append(food)
   payload={'foods':projected}
  else: payload={'products':[{k:v for k,v in food.items() if k in OFF_FIELDS} for food in payload.get('products',[])]}
  item['payload']=json.dumps(payload,separators=(',',':'))
 replay.append(item)
(a.capture_directory/'replay.json').write_text(json.dumps(replay,separators=(',',':')))
print(json.dumps({'records':len(replay),'output':str(a.capture_directory/'replay.json')}))
