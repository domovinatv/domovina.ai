#!/usr/bin/env bash
# Staged rollout na Play production tracku — par uz play-promote.sh, koji
# production od 13.10.2026. šalje na 20 %.
#
#   ./scripts/play-rollout.sh status            # trenutni rollout + crash/ANR rate
#   ./scripts/play-rollout.sh 0.5               # podigni na 50 %
#   ./scripts/play-rollout.sh complete          # 100 %
#   ./scripts/play-rollout.sh halt              # zaustavi (novi korisnici ne dobivaju build)
#   ./scripts/play-rollout.sh resume            # nastavi zaustavljeni
#
# Crash/ANR rate čita Play Developer Reporting API (isti servisni račun,
# scope playdeveloperreporting). API mora biti uključen u GCP projektu
# servisnog računa — bez toga `status` ispiše samo rollout.
set -euo pipefail
cd "$(dirname "$0")/.."

PKG=ai.domovina
ACTION="${1:?status | <0..1> | complete | halt | resume}"
KEY="${PLAY_SA_KEY:-$HOME/.config/play-publisher/domovina-play-publisher.json}"
API=https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$PKG

gcloud auth activate-service-account --key-file="$KEY" >/dev/null 2>&1
TOKEN=$(gcloud auth print-access-token --scopes=https://www.googleapis.com/auth/androidpublisher)
auth=(-H "Authorization: Bearer $TOKEN")

EDIT=$(curl -s --retry 3 "${auth[@]}" -H "Content-Length: 0" -X POST "$API/edits" \
  | ruby -rjson -e 'puts JSON.parse(STDIN.read)["id"]')
TRACK_JSON=$(curl -s --retry 3 "${auth[@]}" "$API/edits/$EDIT/tracks/production")

echo "$TRACK_JSON" | ruby -rjson -e '
  JSON.parse(STDIN.read).fetch("releases", []).each do |r|
    f = r["userFraction"] ? " #{(r["userFraction"] * 100).round(1)} %" : ""
    puts "  production: #{r["name"]} · #{r["status"]}#{f}"
  end'

if [[ "$ACTION" == "status" ]]; then
  curl -s "${auth[@]}" -X DELETE "$API/edits/$EDIT" >/dev/null
  RT=$(gcloud auth print-access-token --scopes=https://www.googleapis.com/auth/playdeveloperreporting)
  for m in crashRateMetricSet anrRateMetricSet; do
    metric=$([[ $m == crash* ]] && echo userPerceivedCrashRate || echo userPerceivedAnrRate)
    # Zadnja 3 dana, po verziji — novi build se vidi odvojeno od starog.
    body=$(ruby -rjson -rdate -e '
      e = Date.today - 1; s = e - 2
      d = ->(x) { { year: x.year, month: x.month, day: x.day } }
      puts({ timelineSpec: { aggregationPeriod: "DAILY", startTime: d.(s), endTime: d.(e) },
             dimensions: ["versionCode"], metrics: [ARGV[0]] }.to_json)' "$metric")
    curl -s -H "Authorization: Bearer $RT" -H "Content-Type: application/json" \
      -X POST "https://playdeveloperreporting.googleapis.com/v1beta1/apps/$PKG/$m:query" -d "$body" \
      | ruby -rjson -e '
        d = JSON.parse(STDIN.read)
        if d["error"]
          puts "  #{ARGV[0]}: nedostupno (#{d["error"]["status"]}) — uključi Play Developer Reporting API u GCP projektu servisnog računa"
          exit
        end
        rows = d.fetch("rows", [])
        puts "  #{ARGV[0]}: nema podataka" if rows.empty?
        rows.group_by { |r| r["dimensions"][0]["stringValue"] }.each do |vc, rs|
          v = rs.map { |r| r["metrics"][0].dig("decimalValue", "value").to_f }
          puts format("  %s vc %s: %.3f %% (zadnji dan)", ARGV[0], vc, v.last * 100)
        end' "$metric"
  done
  exit 0
fi

NEW=$(ACTION="$ACTION" ruby -rjson -e '
  t = JSON.parse(STDIN.read)
  r = t["releases"].find { |x| %w[inProgress halted].include?(x["status"]) } \
      or abort "nema staged releasea (inProgress/halted) na production tracku"
  case ENV["ACTION"]
  when "complete" then r["status"] = "completed"; r.delete("userFraction")
  when "halt"     then r["status"] = "halted"
  when "resume"   then r["status"] = "inProgress"
  else
    f = Float(ENV["ACTION"]) rescue abort("nepoznata radnja: #{ENV["ACTION"]}")
    abort "udio mora biti između 0 i 1 (1 = complete)" unless f > 0 && f < 1
    r["status"] = "inProgress"; r["userFraction"] = f
  end
  t["releases"] = t["releases"].select { |x| x.equal?(r) || x["status"] == "completed" }
  puts t.to_json' <<<"$TRACK_JSON")

curl -s --retry 3 "${auth[@]}" -H "Content-Type: application/json" -X PUT \
  "$API/edits/$EDIT/tracks/production" -d "$NEW" \
  | ruby -rjson -e 'd=JSON.parse(STDIN.read); abort("ERR: "+d["error"]["message"]) if d["error"]'
curl -s --retry 3 "${auth[@]}" -H "Content-Length: 0" -X POST "$API/edits/$EDIT:commit" \
  | ruby -rjson -e 'd=JSON.parse(STDIN.read); abort("ERR: "+d["error"]["message"]) if d["error"]; puts "    committed editId="+d["id"]'
echo "GOTOVO — production: $ACTION"
