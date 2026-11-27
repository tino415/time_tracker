#!/usr/bin/env bash
# Runs on the host: the dev container has no jq.
# Upload an app bundle to a Play track through the Google Play Developer API,
# authenticated with a service account key. Needs curl, openssl and jq.
#
#   tool/play-upload.sh <service-account.json> <package> <track> <bundle.aab> [release-notes]
#   tool/play-upload.sh --check <service-account.json> <package>
#   tool/play-upload.sh --next-code <service-account.json> <package>
#   tool/play-upload.sh --verify-cert <service-account.json> <package> <versionCode>
#   tool/play-upload.sh --release <service-account.json> <package> <track> <versionCode> [release-notes]
#
# An upload goes out as a draft first and is released only when Play signed it
# with the certificate pinned in tool/play-app-signing-cert. That file is not
# tracked: it holds the SHA-256 of your app's signing certificate, as
# --verify-cert prints it for a release Play already holds.
# PLAY_RELEASE_STATUS=draft leaves it as a draft; --release releases it later
# after the same check.
# --check opens an edit and deletes it again: proves the account may touch the
# app without releasing anything.
# --next-code prints the highest versionCode Play knows (the edit's bundles and
# every track's releases) plus 1, through an edit it deletes again.
# --verify-cert prints the certificates Play signed a versionCode with and
# fails unless they are the pinned one.
set -euo pipefail
shopt -s inherit_errexit

api=https://androidpublisher.googleapis.com/androidpublisher/v3/applications
scope=https://www.googleapis.com/auth/androidpublisher
pin_file=$(dirname "$0")/play-app-signing-cert

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
  local response status body
  response=$(request "$@") || return 1
  status=${response##*$'\n'}
  body=${response%$'\n'*}
  [ "$status" -lt 300 ] || { echo "HTTP $status from ${*: -1}: $body" >&2; return 1; }
  printf %s "$body"
}

request() { curl -sS -w "\n%{http_code}" -H "Authorization: Bearer $token" "$@"; }

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
  bundles=$(call "$api/$package/edits/$edit/bundles") || { call -X DELETE "$api/$package/edits/$edit"; return 1; }
  tracks=$(call "$api/$package/edits/$edit/tracks") || { call -X DELETE "$api/$package/edits/$edit"; return 1; }
  call -X DELETE "$api/$package/edits/$edit"
  jq -n --argjson bundles "$bundles" --argjson tracks "$tracks" \
    '([$bundles.bundles[]?.versionCode] + [$tracks.tracks[]?.releases[]?.versionCodes[]? | tonumber]) | (max // 0) + 1'
}

upload() {
  local status=${PLAY_RELEASE_STATUS:-completed} version
  case $status in
    draft | completed) ;;
    *) echo "PLAY_RELEASE_STATUS is draft or completed, not $status" >&2; exit 2 ;;
  esac
  require_pin
  version=$(commit_draft)
  release_if_pinned "$version" "$status"
}

release_if_pinned() {
  local version=$1 status=$2 certs
  require_pin
  if ! certs=$(signing_certs "$version") || ! certs_are_pinned "$certs"; then
    echo "versionCode $version is signed by Play with ${certs:-no certificate}, pinned $(pinned_cert): left as a draft on $track, nothing released" >&2
    exit 1
  fi
  if [ "$status" = draft ]; then
    echo "left versionCode $version as a draft on $track, signed with the pinned certificate"
    return
  fi
  release "$version" "$status"
  echo "released versionCode $version to $track"
}

verify_cert() {
  local certs
  certs=$(signing_certs "$code")
  echo "$certs"
  require_pin
  certs_are_pinned "$certs" || { echo "versionCode $code is signed by Play with $certs, pinned $(pinned_cert)" >&2; return 1; }
}

commit_draft() {
  local edit response version
  edit=$(open_edit)
  response=$(call -X POST -H 'Content-Type: application/octet-stream' --data-binary "@$bundle" \
    "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$package/edits/$edit/bundles?uploadType=media") || { delete_edit "$edit"; return 1; }
  version=$(jq -r .versionCode <<<"$response")
  put_release "$edit" "$version" draft || { delete_edit "$edit"; return 1; }
  call -X POST "$api/$package/edits/$edit:commit" > /dev/null
  echo "$version"
}

release() {
  local version=$1 status=$2 edit
  edit=$(open_edit)
  put_release "$edit" "$version" "$status" || { delete_edit "$edit"; return 1; }
  call -X POST "$api/$package/edits/$edit:commit" > /dev/null
}

delete_edit() { call -X DELETE "$api/$package/edits/$1" > /dev/null; }

put_release() {
  local edit=$1 version=$2 status=$3
  call -X PUT -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg track "$track" --arg code "$version" --arg notes "$notes" --arg status "$status" \
      '{track:$track,releases:[{status:$status,versionCodes:[$code],releaseNotes:(if $notes == "" then [] else [{language:"en-US",text:$notes}] end)}]}')" \
    "$api/$package/edits/$edit/tracks/$track" > /dev/null
}

signing_certs() {
  local version=$1 deadline=$((SECONDS + 120)) certs
  while certs=$(generated_certs "$version") || return 1; [ -z "$certs" ]; do
    [ "$SECONDS" -lt "$deadline" ] || { echo "Play lists no signed APKs for versionCode $version after 2 minutes" >&2; return 1; }
    sleep 10
  done
  echo "$certs"
}

generated_certs() {
  local response status body
  response=$(request "$api/$package/generatedApks/$1") || return 1
  status=${response##*$'\n'}
  body=${response%$'\n'*}
  case $status in
    2??) jq -r '[.generatedApks[]?.certificateSha256Hash] | unique | join(" ")' <<<"$body" ;;
    404) ;;
    *) echo "HTTP $status from generatedApks/$1: $body" >&2; return 1 ;;
  esac
}

certs_are_pinned() { [ "$1" = "$(pinned_cert)" ]; }

pinned_cert() { tr -d '[:space:]' < "$pin_file"; }

require_pin() {
  [ -s "$pin_file" ] || { echo "no $pin_file: write the SHA-256 of Play's app-signing certificate there, as --verify-cert prints it" >&2; exit 2; }
}

usage() { grep '^#   tool/' "$0" | cut -c5- >&2; exit 2; }

if [ "$1" = --check ]; then
  key=$2 package=$3
  token=$(access_token "$key")
  check
elif [ "$1" = --next-code ]; then
  key=$2 package=$3
  token=$(access_token "$key")
  next_code
elif [ "$1" = --verify-cert ]; then
  [ $# -eq 4 ] || usage
  key=$2 package=$3 code=$4
  token=$(access_token "$key")
  verify_cert
elif [ "$1" = --release ]; then
  [ $# -ge 5 ] || usage
  key=$2 package=$3 track=$4 code=$5 notes=${6:-}
  token=$(access_token "$key")
  release_if_pinned "$code" completed
else
  key=$1 package=$2 track=$3 bundle=$4 notes=${5:-}
  token=$(access_token "$key")
  upload
fi
