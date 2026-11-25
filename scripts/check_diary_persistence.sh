#!/bin/bash
set -euo pipefail
: "${FIRESTORE_EMULATOR_HOST:?Run this script through firebase emulators:exec --only firestore,auth}"
: "${FIREBASE_AUTH_EMULATOR_HOST:?Start the Auth emulator too}"
if [[ "$FIRESTORE_EMULATOR_HOST" != "127.0.0.1:8080" || "$FIREBASE_AUTH_EMULATOR_HOST" != "127.0.0.1:9099" ]]; then
  echo "Native persistence tests require the loopback emulator ports in firebase.json."
  exit 1
fi
xcodebuild test -project MyFitPlate.xcodeproj -scheme MyFitPlate \
  -destination "platform=iOS Simulator,id=${1:?Pass the simulator ID}" \
  -derivedDataPath "${DIARY_TEST_DERIVED_DATA:-/tmp/myfitplate-diary-tests}" \
  -only-testing:MyFitPlateTests/DiaryPersistenceIntegrationTests \
  -parallel-testing-enabled NO MYFITPLATE_EMULATOR_TESTS=YES CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
npm test --prefix tests/firebase-rules
