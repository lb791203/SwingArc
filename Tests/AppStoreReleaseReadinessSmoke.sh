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
test "$(grep -Fc 'INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "SwingArc 需要将您主动导出的标注图片和视频保存到照片图库。";' "$project")" = "2"

sources_phase="$(sed -n '/\/\* Begin PBXSourcesBuildPhase section \*\//,/\/\* End PBXSourcesBuildPhase section \*\//p' "$project")"
printf '%s\n' "$sources_phase" | grep -Fq 'C90000000000000000000001 /* AppInformation.swift in Sources */'
printf '%s\n' "$sources_phase" | grep -Fq 'C90000000000000000000003 /* AboutPrivacyView.swift in Sources */'

grep -Fqx -- '- 副标题：`专业画线与P1–P8分析`' "$metadata"
for heading in \
  '• 手动录像与视频导入' \
  '• 慢动作与逐帧回放' \
  '• P1–P8 本地识别' \
  '• P 点人工修正' \
  '• 专业画线' \
  '• 本地记录与标注导出'; do
  grep -Fqx -- "$heading" "$metadata"
done
grep -Fqx -- '首次发布：支持手动录像、视频导入、慢动作与逐帧回放、P1–P8 本地识别和人工修正、专业画线、本地项目记录及标注图片/视频导出。' "$metadata"
grep -Fqx -- '提示：P1–P8 自动识别结果仅用于运动训练参考，不能替代专业教练意见。识别效果会受到机位、光线、遮挡和视频完整度影响。P6 和 P8 缺少可靠杆身证据时会显示“未识别”，SwingArc 不会用固定时间或视频百分比生成假结果。' "$metadata"
for marker in \
  '1. Launch SwingArc.' \
  '3. The local P1–P8 analysis starts automatically.' \
  '5. Tap **修正 P 点** to choose an exact source frame for a stage.' \
  '6. Tap **画线**, create a line or circle, switch to **选择**, and move the annotation.' \
  '7. Use **导出** to save/share an annotated frame or video.' \
  '8. Return home, open **记录**, reopen the project, and verify the correction and drawing remain; the project can also be deleted there.'; do
  grep -Fqx -- "$marker" "$review_notes"
done
grep -Fqx -- '    <li>照片图库用于选择您主动导入的视频，以及保存您主动导出的标注图片和视频。</li>' "$privacy_page"
grep -Fqx -- '    <li>The photo library lets you select videos to import and save annotated photos and videos you choose to export.</li>' "$privacy_page"
grep -Fqx -- '  <p>您可以从系统照片选择器导入挥杆视频，并在主动选择导出时把标注图片和视频保存到照片图库。</p>' "$support_page"
grep -Fqx -- '  <p lang="en">SwingArc supports manual recording, video import, playback, P1–P8 stage detection, and annotation locally on iPhone. It does not upload your videos or use the microphone. If camera access was denied, restore it in iOS Settings. Unresolved P points can be corrected by choosing an exact source frame. You can save annotated photos and videos you choose to export to Photos. For help, email <a href="mailto:liang.ctp@gmail.com">liang.ctp@gmail.com</a> with your iPhone model, iOS version, app version, and reproduction steps.</p>' "$support_page"
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
  if grep -Eiq '自动练习|自动捕捉|自动录制|技术评分|练习建议|挥杆轨迹|动作反馈|语音反馈|姿态辅助|姿态骨架|姿态叠加|教练建议|训练计划|练习计划|评分|语音指导|语音提示|轨迹指导' "$file"; then
    echo "Deferred Chinese feature claim remains in $file" >&2
    exit 1
  fi

  while IFS= read -r line; do
    if printf '%s\n' "$line" | grep -Eiq 'automatic[ -](practice|capture)|DTL|FACE[- ]?ON|pose (assistance|overlay)|coaching|drills?|scoring|speech feedback|voice feedback|trajectory coaching'; then
      if ! printf '%s\n' "$line" | grep -Eiq '\b(no|not|without|does not|doesn.t)\b'; then
        echo "Deferred English feature claim remains in $file: $line" >&2
        exit 1
      fi
    fi
  done < "$file"
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
