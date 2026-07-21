#!/bin/zsh

set -euo pipefail

test -f SwingArc/LaunchScreen.storyboard
test -f SwingArc/Assets.xcassets/LaunchMark.imageset/LaunchMark.svg
test -f SwingArc/Assets.xcassets/LaunchBackground.colorset/Contents.json

grep -q 'image="LaunchMark"' SwingArc/LaunchScreen.storyboard
grep -q 'name="LaunchBackground"' SwingArc/LaunchScreen.storyboard
grep -q 'INFOPLIST_KEY_UILaunchStoryboardName = LaunchScreen;' /Users/liangbo/Documents/SwingArcProject/SwingArcProject.xcodeproj/project.pbxproj

print "Launch brand smoke passed"
