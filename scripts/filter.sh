#!/bin/bash
# Alfred Script Filter for the Dropbox Abuse Report workflow.
#
# Receives the URL the user typed (as $1). Emits Alfred JSON offering the
# three report categories. Each item carries the URL as its `arg` and the
# chosen category as the `explanation` workflow variable, which submit.sh reads.
set -euo pipefail

URL="${1:-}"
# Trim leading/trailing whitespace.
URL="${URL#"${URL%%[![:space:]]*}"}"
URL="${URL%"${URL##*[![:space:]]}"}"

# Minimal JSON string escaper: backslash, double-quote, and the control
# characters that would otherwise produce invalid JSON.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Nothing typed yet, or it does not look like a URL: show guidance and block
# actioning (valid=false) so the user cannot submit garbage.
if [[ -z "$URL" || ! "$URL" =~ ^https?:// ]]; then
  cat <<JSON
{"items":[{
  "title": "Paste the Dropbox link to report",
  "subtitle": "e.g. https://www.dropbox.com/scl/fi/... or a dl.dropboxusercontent.com link",
  "valid": false,
  "icon": {"path": "icon.png"}
}]}
JSON
  exit 0
fi

E_URL="$(json_escape "$URL")"

emit() { # label  explanation  subtitle
  cat <<JSON
{
  "title": "Report as $1",
  "subtitle": "$3",
  "arg": "$E_URL",
  "variables": {"explanation": "$2"},
  "icon": {"path": "icon.png"}
}
JSON
}

printf '{"items":['
emit "phishing" "phishing" "Fake login / credential-stealing content"
printf ','
emit "fraud"    "fraud"    "Scams, financial fraud, deceptive content"
printf ','
emit "abuse"    "abuse"    "Spam or other abusive content"
printf ']}'
