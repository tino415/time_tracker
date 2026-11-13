#!/usr/bin/env bash
# Runs on the host: the dev container has no jq.
# Upload an app bundle to a Play track through the Google Play Developer API,
# authenticated with a service account key. Needs curl, openssl and jq.
#
#   tool/play-upload.sh <service-account.json> <package> <track> <bundle.aab> [release-notes]
#   tool/play-upload.sh --check <service-account.json> <package>
#   tool/play-upload.sh --next-code <service-account.json> <package>
#
# --check opens an edit and deletes it again: proves the account may touch the
# app without releasing anything.
# --next-code prints the highest versionCode Play knows (the edit's bundles and
# every track's releases) plus 1, through an edit it deletes again.
set -euo pipefail

api=https://androidpublisher.googleapis.com/androidpublisher/v3/applications
scope=https://www.googleapis.com/auth/androidpublisher

base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

access_token() {
  local key=$1 now header claims signing_input
  now=$(date +%s)
  header=$(jq -nc '{alg:"RS256",typ:"JWT"}' | base64url)
  claims=$(jq -nc --arg iss "$(jq -r .client_email "$key")" --arg scope "$scope" --argjson now "$now" \
    '{iss:$iss,scope:$scope,aud:"https://oauth2.googleapis.com/token",iat:$now,exp:($now+3600)}' | base64url)
  signing_input="$header.$claims"
  local signature
  signature=$(printf %s "$signing_input" | openssl dgst -sha256 -sign <(jq -r .private_key "$key") | base64url)
  curl -fsS https://oauth2.googleapis.com/token \
    -d grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer -d "assertion=$signing_input.$signature" | jq -r .access_token
}

call() {
  local body status
  body=$(curl -sS -w "\n%{http_code}" -H "Authorization: Bearer $token" "$@") || return 1
  status=${body##*$'\n'}
  body=${body%$'\n'*}
  [ "$status" -lt 300 ] || { echo "HTTP $status from ${*: -1}: $body" >&2; return 1; }
  printf %s "$body"
}

open_edit() { call -X POST -H 'Content-Type: application/json' -d '{}' "$api/$package/edits" | jq -r .id; }

check() {
  local edit
  edit=$(open_edit)
  call -X DELETE "$api/$package/edits/$edit"
  echo "ok: $package is reachable as $(jq -r .client_email "$key")"
}

next_code() {
  local edit bundles tracks
  edit=$(open_edit)
  bundles=$(call "$api/$package/edits/$edit/bundles")
  tracks=$(call "$api/$package/edits/$edit/tracks")
  call -X DELETE "$api/$package/edits/$edit"
  jq -n --argjson bundles "$bundles" --argjson tracks "$tracks" \
    '([$bundles.bundles[]?.versionCode] + [$tracks.tracks[]?.releases[]?.versionCodes[]? | tonumber]) | (max // 0) + 1'
}

upload() {
  local edit version response
  edit=$(open_edit)
  response=$(call -X POST -H 'Content-Type: application/octet-stream' --data-binary "@$bundle" \
    "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$package/edits/$edit/bundles?uploadType=media") || { echo "$response" >&2; return 1; }
  version=$(jq -r .versionCode <<<"$response")
  call -X PUT -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg track "$track" --arg code "$version" --arg notes "$notes" --arg status "${PLAY_RELEASE_STATUS:-completed}" \
      '{track:$track,releases:[{status:$status,versionCodes:[$code],releaseNotes:(if $notes == "" then [] else [{language:"en-US",text:$notes}] end)}]}')" \
    "$api/$package/edits/$edit/tracks/$track" > /dev/null
  call -X POST "$api/$package/edits/$edit:commit" > /dev/null
  echo "released versionCode $version to $track"
}

if [ "$1" = --check ]; then
  key=$2 package=$3
  token=$(access_token "$key")
  check
elif [ "$1" = --next-code ]; then
  key=$2 package=$3
  token=$(access_token "$key")
  next_code
else
  key=$1 package=$2 track=$3 bundle=$4 notes=${5:-}
  token=$(access_token "$key")
  upload
fi
