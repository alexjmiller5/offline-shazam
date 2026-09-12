app := "OfflineShazam"
destination := env("IOS_TEST_DESTINATION", "platform=iOS Simulator,name=iPhone 17")
derived := env("IOS_DERIVED_DATA", env("HOME") + "/Library/Developer/Xcode/DerivedData/offline-shazam")

gen:
    "$(realpath "$(command -v xcodegen)")" generate

dev: gen
    open {{app}}.xcodeproj

test: gen
    xcodebuild -quiet -project {{app}}.xcodeproj -scheme {{app}} -derivedDataPath "{{derived}}" -destination "{{destination}}" CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES -parallel-testing-enabled NO test

check: gen
    xcodebuild -quiet -project {{app}}.xcodeproj -scheme {{app}} -derivedDataPath "{{derived}}" -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build

build: gen
    xcodebuild -quiet -project {{app}}.xcodeproj -scheme {{app}} -derivedDataPath "{{derived}}" -destination "generic/platform=iOS" -configuration Debug -allowProvisioningUpdates DEVELOPMENT_TEAM="${IOS_TEAM_ID:?Set IOS_TEAM_ID}" build

deploy: gen
    xcodebuild -quiet -project {{app}}.xcodeproj -scheme {{app}} -derivedDataPath "{{derived}}" -destination "generic/platform=iOS" -configuration Release DEVELOPMENT_TEAM="${IOS_TEAM_ID:?Set IOS_TEAM_ID}" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" PROVISIONING_PROFILE_SPECIFIER="${IOS_PROFILE:?Set IOS_PROFILE}" build
    xcrun devicectl device install app --device "${IOS_DEVICE_ID:?Set IOS_DEVICE_ID}" "{{derived}}/Build/Products/Release-iphoneos/{{app}}.app"
