#!/usr/bin/env bash
set -euo pipefail

SCANNER_URL="https://scanner.tradingview.com/america/scan"
LOGO_BASE_URL="https://s3-symbol-logo.tradingview.com"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dockx/stock-logos"
TMP_DIR="$(mktemp -d)"
PAGE_SIZE=1000

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CACHE_DIR"

echo "Consultando total de acciones en TradingView (stocks-usa)..."
TOTAL_COUNT="$(curl -s "$SCANNER_URL" \
  -H 'content-type: application/json' \
  --data-raw '{"markets":["america"],"symbols":{"query":{"types":["stock"]},"tickers":[]},"columns":["name","logoid"],"range":[0,1]}' \
  | jq -r '.totalCount')"

if [[ -z "$TOTAL_COUNT" || "$TOTAL_COUNT" == "null" ]]; then
  echo "No se pudo obtener totalCount desde TradingView scanner."
  exit 1
fi

echo "Total detectado: $TOTAL_COUNT"
echo "Extrayendo símbolos + logoid en bloques de $PAGE_SIZE..."

OFFSET=0
while [[ "$OFFSET" -lt "$TOTAL_COUNT" ]]; do
  END=$((OFFSET + PAGE_SIZE - 1))
  if [[ "$END" -ge "$TOTAL_COUNT" ]]; then
    END=$((TOTAL_COUNT - 1))
  fi

  echo "Bloque [$OFFSET..$END]"
  curl -s "$SCANNER_URL" \
    -H 'content-type: application/json' \
    --data-raw "{\"markets\":[\"america\"],\"symbols\":{\"query\":{\"types\":[\"stock\"]},\"tickers\":[]},\"columns\":[\"name\",\"logoid\"],\"range\":[$OFFSET,$END]}" \
    | jq -r '.data[] | "\(.d[0])\t\(.d[1])"' >> "$TMP_DIR/symbol_logoid.tsv"

  OFFSET=$((END + 1))
done

if [[ ! -s "$TMP_DIR/symbol_logoid.tsv" ]]; then
  echo "No se obtuvieron pares symbol/logoid."
  exit 1
fi

echo "Descargando logos a $CACHE_DIR ..."
export LOGO_BASE_URL CACHE_DIR
  cat "$TMP_DIR/symbol_logoid.tsv" \
  | awk 'NF>=2 && $1!="" && $2!="" {print $1 "\t" $2}' \
  | sort -u \
  | xargs -P 16 -I {} bash -c '
      line="$1"
      symbol="${line%%$'\''\t'\''*}"
      logoid="${line#*$'\''\t'\''}"
      key="$(printf "%s" "$symbol" | tr "[:upper:]" "[:lower:]" | sed -E "s/[^a-z0-9]+/_/g")"
      [[ -z "$key" ]] && exit 0
      curl -fsSL "$LOGO_BASE_URL/$logoid.svg" -o "$CACHE_DIR/$key.logo" || true
    ' _ {}

DOWNLOADED="$(find "$CACHE_DIR" -maxdepth 1 -type f -name '*.logo' | wc -l | tr -d ' ')"
echo "Prefetch finalizado. Logos en caché: $DOWNLOADED"
