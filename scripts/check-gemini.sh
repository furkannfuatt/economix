#!/bin/zsh
# Config/Secrets.xcconfig'teki anahtarla uygulamanın kullandığı istek biçimini dener.
# Anahtar ekrana yazılmaz. Kullanım: scripts/check-gemini.sh [model]
set -euo pipefail
cd "$(dirname "$0")/.."
MODEL="${1:-gemini-3.8-flash}"
KEY=$(sed -n 's/^[[:space:]]*GEMINI_API_KEY[[:space:]]*=[[:space:]]*//p' Config/Secrets.xcconfig | tr -d '[:space:]')
if [[ -z "$KEY" || "$KEY" == "BURAYA_ANAHTARINI_YAZ" ]]; then
  echo "Config/Secrets.xcconfig içinde GEMINI_API_KEY boş." >&2
  exit 1
fi
BODY='{
  "systemInstruction": {"parts": [{"text": "Kısa ve Türkçe yanıt ver."}]},
  "contents": [{"role": "user", "parts": [{"text": "{\"currency\":\"TRY\",\"months\":[{\"month\":\"2026-09\",\"income\":50000,\"expense\":46000}]}"}]}],
  "generationConfig": {
    "maxOutputTokens": 2048,
    "responseMimeType": "application/json",
    "responseJsonSchema": {
      "type": "object",
      "properties": {"summary": {"type": "string"}, "savingsRatePercent": {"type": "number"}},
      "required": ["summary", "savingsRatePercent"],
      "additionalProperties": false
    }
  }
}'
curl -sS -w '\nHTTP %{http_code}\n' \
  -H "x-goog-api-key: $KEY" \
  -H "X-Ios-Bundle-Identifier: com.furkanfuat.ecoomix" \
  -H "Content-Type: application/json" \
  -d "$BODY" \
  "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"
