#!/usr/bin/env bash
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
project="$root/SwingArcProject.xcodeproj/project.pbxproj"
privacy="$root/SwingArc/PrivacyInfo.xcprivacy"
icons="$root/SwingArc/Assets.xcassets/AppIcon.appiconset"
metadata="$root/docs/app-store/metadata/zh-Hans.md"
privacy_page="$root/docs/app-store/privacy/index.html"
support_page="$root/docs/app-store/support/index.html"
about_model="$root/SwingArc/Models/AppInformation.swift"
about_view="$root/SwingArc/Views/AboutPrivacyView.swift"
review_notes="$root/docs/app-store/metadata/review-notes.md"
checklist="$root/docs/app-store/submission-checklist.md"

test -f "$project"
test -f "$privacy"
test -f "$metadata"
test -f "$privacy_page"
test -f "$support_page"
test -f "$about_model"
test -f "$about_view"
test -f "$review_notes"
test -f "$checklist"
plutil -lint "$project" "$privacy" >/dev/null

grep -q 'PrivacyInfo.xcprivacy in Resources' "$project"
grep -q 'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;' "$project"
grep -q 'INFOPLIST_KEY_NSCameraUsageDescription' "$project"
grep -q 'INFOPLIST_KEY_NSPhotoLibraryUsageDescription' "$project"
grep -q 'INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription' "$project"
grep -q 'TARGETED_DEVICE_FAMILY = 1;' "$project"
grep -q 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;' "$project"
grep -q 'SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;' "$project"
grep -q 'MARKETING_VERSION = 1.0;' "$project"
grep -q 'CURRENT_PROJECT_VERSION = 1;' "$project"
grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.liangbo.swingarc;' "$project"
grep -q 'IPHONEOS_DEPLOYMENT_TARGET = 17.0;' "$project"
grep -q 'INFOPLIST_KEY_CFBundleDisplayName = SwingArc;' "$project"
grep -q 'https://lb791203.github.io/SwingArc/app-store/privacy/' "$about_model"
grep -q 'https://lb791203.github.io/SwingArc/app-store/support/' "$about_model"
grep -q 'AboutPrivacyView.swift in Sources' "$project"
grep -q 'AppInformation.swift in Sources' "$project"
grep -q '手动录像' "$metadata"
grep -q 'P1–P8' "$metadata"
grep -q '专业画线' "$metadata"
grep -q '人工修正' "$metadata"
grep -q '免费' "$checklist"
grep -q 'ICP' "$checklist"
grep -q 'DSA' "$checklist"

if grep -q 'NSMicrophoneUsageDescription' "$project"; then
  echo "Release project must not declare microphone access." >&2
  exit 1
fi

test "$(plutil -extract NSPrivacyTracking raw -o - "$privacy")" = "false"
test "$(plutil -extract NSPrivacyCollectedDataTypes raw -o - "$privacy")" = "0"
plutil -p "$privacy" | grep -q 'NSPrivacyAccessedAPICategoryUserDefaults'
plutil -p "$privacy" | grep -q 'CA92.1'
plutil -p "$privacy" | grep -q 'NSPrivacyAccessedAPICategorySystemBootTime'
plutil -p "$privacy" | grep -q '35F9.1'

for icon in "$icons"/*.png; do
  test "$(sips -g pixelWidth "$icon" 2>/dev/null | awk '/pixelWidth/ {print $2}')" = "1024"
  test "$(sips -g pixelHeight "$icon" 2>/dev/null | awk '/pixelHeight/ {print $2}')" = "1024"
  test "$(sips -g hasAlpha "$icon" 2>/dev/null | awk '/hasAlpha/ {print $2}')" = "no"
done

for file in "$metadata" "$review_notes" "$privacy_page" "$support_page"; do
  for forbidden in \
    '自动练习' \
    '技术评分' \
    '练习建议' \
    '挥杆轨迹' \
    '动作反馈' \
    '语音反馈'; do
    if grep -q "$forbidden" "$file"; then
      echo "Deferred feature claim '$forbidden' remains in $file" >&2
      exit 1
    fi
  done
done

ruby - "$metadata" <<'RUBY'
text = File.read(ARGV.fetch(0))
name = text[/^- 名称：`([^`]+)`$/, 1] or abort "Missing App Store name."
subtitle = text[/^- 副标题：`([^`]+)`$/, 1] or abort "Missing App Store subtitle."
promotional_text = text[/^## 宣传文本\n\n(.+?)(?=\n\n## )/m, 1]&.strip or abort "Missing promotional text."
description = text[/^## 描述\n\n(.+?)(?=\n\n## )/m, 1]&.strip or abort "Missing description."
keywords = text[/^## 关键词\n\n`([^`]+)`/, 1] or abort "Missing keywords."

{
  "App Store name" => [name.length, 30],
  "App Store subtitle" => [subtitle.length, 30],
  "Promotional text" => [promotional_text.length, 170],
  "Description" => [description.length, 4_000]
}.each do |label, (length, limit)|
  abort "#{label} exceeds #{limit} characters." if length > limit
end

abort "Keywords exceed 100 UTF-8 bytes." if keywords.bytesize > 100
RUBY

for page in "$root/docs/app-store/index.html" "$privacy_page" "$support_page"; do
  parser_output="$(xmllint --html --noout "$page" 2>&1 || true)"
  unexpected_output="$(printf '%s\n' "$parser_output" | \
    grep -Ev 'HTML parser error : Tag main invalid|^<main>$|^     \^$' || true)"
  if [[ -n "$unexpected_output" ]]; then
    printf '%s\n' "$unexpected_output" >&2
    exit 1
  fi
done

echo "App Store release readiness smoke: PASS"
