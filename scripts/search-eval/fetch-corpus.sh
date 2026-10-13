#!/usr/bin/env bash
# Skini katalog (search.json + listinge kanala) u radni direktorij za
# run.py/capture.py. Korištenje: cd <radni-dir> && scripts/search-eval/fetch-corpus.sh
set -euo pipefail
curl -s https://cdn.domovina.ai/channels/data/search.json -o search.json
curl -s https://cdn.domovina.ai/channels/data/index.json -o index.json
mkdir -p ch
python3 -c "import json;print('\n'.join(c['id'] for c in json.load(open('index.json'))['channels']))" \
  | xargs -P8 -I{} curl -s https://cdn.domovina.ai/channels/data/{}.json -o ch/{}.json
echo "kanala: $(ls ch | wc -l)"
