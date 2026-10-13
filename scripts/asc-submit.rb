#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Pošalji VEĆ UPLOADAN TestFlight build na App Store review — iOS pandan
# play-promote.sh. Flow iz docs/mobile-release-pipeline.md („Production
# promocija"), kojim je 2.0.74 ručno poslan 10.7.2026.:
#
#   appStoreVersion (nađi editabilnu ili stvori) → whatsNew po lokalizaciji →
#   attach build → reviewSubmission + item → submitted=true
#
#   ./scripts/asc-submit.rb <build> --notes-hr "…" [--notes-en "…"]            # plan, ništa ne piše
#   ./scripts/asc-submit.rb <build> --notes-hr "…" [--notes-en "…"] --submit   # stvarno pošalji
#
# Od 13.10.2026. zadano: phased release (7 dana, --no-phased gasi) i smoke
# vrata (scripts/smoke-gate.sh; --skip-smoke-gate za svjesnu iznimku).
#
# Bez --submit skripta samo čita i ispiše što BI napravila. Lokalizacije bez
# vlastitog teksta dobiju --notes-en ako je zadan (en-*), inače --notes-hr.
# Build mora biti processingState=VALID; verzija App Storea = CFBundleShortVersionString
# builda (preReleaseVersion), ne pubspec.
require 'json'
require 'net/http'
require 'open3'
require 'uri'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

BUNDLE_ID = 'ai.domovina'
HOST      = 'api.appstoreconnect.apple.com'
EDITABLE  = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze

build_no = ARGV.find { |a| a =~ /\A\d+\z/ } or abort 'build broj obavezan (npr. 177)'
opt      = ->(k) { i = ARGV.index(k); i && ARGV[i + 1] }
notes_hr = opt.('--notes-hr') or abort '--notes-hr obavezan (whatsNew je obavezan za update)'
notes_en = opt.('--notes-en')
SUBMIT   = ARGV.include?('--submit')
PHASED   = !ARGV.include?('--no-phased')
SMOKE_GATE = !ARGV.include?('--skip-smoke-gate')

def token
  @token ||= begin
    env = { 'ASC_KEY_ID' => ENV['ASC_KEY_ID'] || '25KYCN22QD',
            'ASC_ISSUER_ID' => ENV['ASC_ISSUER_ID'] || '69a6de85-f7cc-47e3-e053-5b8c7c11a4d1' }
    env['ASC_KEY_PATH'] = ENV['ASC_KEY_PATH'] ||
      File.join(Dir.home, '.appstoreconnect/private_keys', "AuthKey_#{env['ASC_KEY_ID']}.p8")
    out, err, st = Open3.capture3(env, 'ruby', File.join(__dir__, 'asc-token.rb'))
    abort "ASC token: #{err}" unless st.success?
    out.strip
  end
end

def asc(verb, path, body = nil)
  uri = URI("https://#{HOST}#{path}")
  req = Net::HTTP.const_get(verb.capitalize).new(uri, 'Authorization' => "Bearer #{token}",
                                                      'Content-Type' => 'application/json')
  req.body = body.to_json if body
  res = Net::HTTP.start(uri.host, 443, use_ssl: true) { |h| h.request(req) }
  data = res.body.to_s.empty? ? {} : JSON.parse(res.body)
  unless res.code.to_i.between?(200, 299)
    errs = (data['errors'] || []).map { |e| "#{e['title']}: #{e['detail']}" }.join(' | ')
    abort "ASC #{res.code} #{verb.upcase} #{path}\n  #{errs}"
  end
  data
end

# Zapisujuća operacija: u planu se samo ispiše.
def write(desc, verb, path, body = nil)
  puts "  #{SUBMIT ? '→' : '(plan)'} #{desc}"
  SUBMIT ? asc(verb, path, body) : nil
end

app_id = asc(:get, "/v1/apps?filter%5BbundleId%5D=#{BUNDLE_ID}").dig('data', 0, 'id') or abort 'app nije nađen'

# ── build ────────────────────────────────────────────────────────────────────
b = asc(:get, "/v1/builds?filter%5Bapp%5D=#{app_id}&filter%5Bversion%5D=#{build_no}&include=preReleaseVersion")
build = b.dig('data', 0) or abort "build #{build_no} ne postoji na App Store Connectu"
state = build.dig('attributes', 'processingState')
abort "build #{build_no} je #{state}, treba VALID" unless state == 'VALID'
abort "build #{build_no} je istekao" if build.dig('attributes', 'expired')
version = (b['included'] || []).find { |x| x['type'] == 'preReleaseVersions' }&.dig('attributes', 'version') \
  or abort 'ne mogu pročitati verziju builda (preReleaseVersion)'
puts "==> build #{build_no} · verzija #{version} · VALID"

# ── smoke vrata ──────────────────────────────────────────────────────────────
# Nightly zapisuje ishod smokea po buildu (scripts/smoke-gate.sh). Build koji
# nije prošao smoke na uređajima farme ne ide u review bez --skip-smoke-gate.
if SMOKE_GATE
  gate = File.join(__dir__, 'smoke-gate.sh')
  out, st = Open3.capture2e(gate, build_no)
  puts out.lines.map { |l| "    #{l}" }.join
  abort "smoke vrata zatvorena za build #{build_no} (--skip-smoke-gate za iznimku)" unless st.success?
end

# ── appStoreVersion ──────────────────────────────────────────────────────────
vers = asc(:get, "/v1/apps/#{app_id}/appStoreVersions?filter%5Bplatform%5D=IOS&limit=10")['data']
live = vers.find { |v| v.dig('attributes', 'appStoreState') == 'READY_FOR_SALE' }
puts "    na App Storeu sad: #{live&.dig('attributes', 'versionString') || '—'}"
if vers.any? { |v| v.dig('attributes', 'versionString') == version && !EDITABLE.include?(v.dig('attributes', 'appStoreState')) }
  abort "verzija #{version} već postoji i nije editabilna (u reviewu ili objavljena)"
end
editable = vers.find { |v| EDITABLE.include?(v.dig('attributes', 'appStoreState')) }

if editable
  ver_id = editable['id']
  cur = editable.dig('attributes', 'versionString')
  puts "==> editabilna verzija #{cur} (#{editable.dig('attributes', 'appStoreState')})"
  if cur != version
    write("versionString #{cur} → #{version}", :patch, "/v1/appStoreVersions/#{ver_id}",
          { data: { type: 'appStoreVersions', id: ver_id, attributes: { versionString: version } } })
  end
else
  puts '==> nema editabilne verzije — stvaram novu'
  r = write("POST appStoreVersion #{version} (release AFTER_APPROVAL)", :post, '/v1/appStoreVersions',
            { data: { type: 'appStoreVersions',
                      attributes: { platform: 'IOS', versionString: version, releaseType: 'AFTER_APPROVAL' },
                      relationships: { app: { data: { type: 'apps', id: app_id } } } } })
  ver_id = r&.dig('data', 'id')
end

# ── whatsNew ─────────────────────────────────────────────────────────────────
# Nova verzija naslijedi lokalizacije prethodne; u planu ih čitamo s žive.
loc_src = ver_id || live&.dig('id')
locs = loc_src ? asc(:get, "/v1/appStoreVersions/#{loc_src}/appStoreVersionLocalizations")['data'] : []
locs.each do |l|
  code = l.dig('attributes', 'locale')
  text = code.start_with?('en') && notes_en ? notes_en : notes_hr
  next unless ver_id # plan za novu verziju: lokalizacije još ne postoje

  write("whatsNew [#{code}] (#{text.length} znakova)", :patch, "/v1/appStoreVersionLocalizations/#{l['id']}",
        { data: { type: 'appStoreVersionLocalizations', id: l['id'], attributes: { whatsNew: text } } })
end
puts "  (plan) whatsNew za lokalizacije: #{locs.map { |l| l.dig('attributes', 'locale') }.join(', ')}" unless ver_id

# ── build → verzija ──────────────────────────────────────────────────────────
write("attach build #{build_no}", :patch, "/v1/appStoreVersions/#{ver_id || 'NOVA'}/relationships/build",
      { data: { type: 'builds', id: build['id'] } })

# ── phased release ───────────────────────────────────────────────────────────
# 7-dnevna postupna objava (1 → 2 → 5 → 10 → 20 → 50 → 100 % korisnika s
# automatskim ažuriranjem), pauzabilna u App Store Connectu. Ako nakon
# odobrenja iskrsne crash, pauza zaustavi širenje dok fix ne prođe review.
if PHASED
  existing = ver_id && asc(:get, "/v1/appStoreVersions/#{ver_id}/appStoreVersionPhasedRelease")['data']
  if existing
    puts "    phased release već postoji (#{existing.dig('attributes', 'phasedReleaseState')})"
  else
    write('POST appStoreVersionPhasedRelease (ACTIVE, 7 dana)', :post, '/v1/appStoreVersionPhasedReleases',
          { data: { type: 'appStoreVersionPhasedReleases', attributes: { phasedReleaseState: 'ACTIVE' },
                    relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: ver_id || 'NOVA' } } } } })
  end
end

# ── review submission ────────────────────────────────────────────────────────
open_sub = asc(:get, "/v1/reviewSubmissions?filter%5Bapp%5D=#{app_id}&filter%5Bplatform%5D=IOS" \
                     '&filter%5Bstate%5D=READY_FOR_REVIEW&limit=1')['data'].first
sub_id = open_sub&.dig('id')
unless sub_id
  r = write('POST reviewSubmission', :post, '/v1/reviewSubmissions',
            { data: { type: 'reviewSubmissions', attributes: { platform: 'IOS' },
                      relationships: { app: { data: { type: 'apps', id: app_id } } } } })
  sub_id = r&.dig('data', 'id')
end
write('POST reviewSubmissionItem (appStoreVersion)', :post, '/v1/reviewSubmissionItems',
      { data: { type: 'reviewSubmissionItems',
                relationships: { reviewSubmission: { data: { type: 'reviewSubmissions', id: sub_id || 'NOVA' } },
                                 appStoreVersion: { data: { type: 'appStoreVersions', id: ver_id || 'NOVA' } } } } })
r = write('PATCH reviewSubmission submitted=true', :patch, "/v1/reviewSubmissions/#{sub_id || 'NOVA'}",
          { data: { type: 'reviewSubmissions', id: sub_id || 'NOVA', attributes: { submitted: true } } })

if SUBMIT
  puts "GOTOVO — #{version} (#{build_no}) poslan na review: #{r&.dig('data', 'attributes', 'state')}"
else
  puts 'PLAN — ništa nije zapisano. Dodaj --submit za stvarno slanje.'
end
