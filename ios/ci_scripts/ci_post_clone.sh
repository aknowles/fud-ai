#!/bin/sh
# Xcode Cloud only: sign as the team and app ID of the Xcode Cloud product.
# CI_TEAM_ID and CI_BUNDLE_ID come from Xcode Cloud, so no IDs live in the repo.
set -eu

ios="$CI_PRIMARY_REPOSITORY_PATH/ios"

sed -i '' \
  -e "s/DEVELOPMENT_TEAM = 23RV7FYH36;/DEVELOPMENT_TEAM = $CI_TEAM_ID;/" \
  -e "s/com\.apoorvdarshan\.calorietracker/$CI_BUNDLE_ID/g" \
  "$ios/calorietracker.xcodeproj/project.pbxproj"

# No iCloud or associated domains, as in the device build.
ent="$ios/calorietracker/calorietracker.entitlements"
for key in associated-domains icloud-container-identifiers icloud-services; do
  /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.$key" "$ent"
done

# Hide the iCloud backup screens; CKContainer.default() crashes without the entitlement.
git -C "$CI_PRIMARY_REPOSITORY_PATH" apply "$ios/ci_scripts/cloud-build.patch"
