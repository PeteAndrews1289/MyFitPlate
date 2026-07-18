# App Store Privacy - 2.3

This is the release-side reconciliation record for App Store Connect. It does not replace the
public [Privacy Policy](privacy_policy.md), Apple's privacy questionnaire, or legal review.

Last reconciled: July 17, 2026

## Published Summary

The App Store Connect privacy preview published before the 2.3 candidate lists these 13 data
types:

| Category | Data type | Current relationship |
| --- | --- | --- |
| Contact Info | Email Address | Linked to the user |
| Health & Fitness | Health | Linked to the user |
| Health & Fitness | Fitness | Linked to the user |
| Location | Precise Location | Linked to the user |
| Location | Coarse Location | Linked to the user |
| User Content | Photos or Videos | Linked to the user |
| User Content | Other User Content | Linked to the user |
| Identifiers | User ID | Linked to the user |
| Identifiers | Device ID | Not linked to the user |
| Usage Data | Product Interaction | Linked to the user |
| Diagnostics | Crash Data | Not linked to the user |
| Diagnostics | Performance Data | Not linked to the user |
| Diagnostics | Other Diagnostic Data | Not linked to the user |

The published preview states that MyFitPlate does not use data to track users. Reopen each answer
in App Store Connect before submission if Apple changes its questionnaire or an SDK/configuration
change alters collection behavior; the category preview alone does not show every purpose answer.

## Release Reconciliation

- Email address and Firebase user ID support authentication, account recovery, synchronization,
  and deletion.
- Health and fitness records support nutrition, training, recovery, reports, and user-requested
  Apple Health synchronization. They are not used for advertising or tracking.
- Precise location is used for a user-started outdoor route and may continue in the background
  only while that recording is active.
- Google Analytics may derive coarse location from the connection used for an analytics event.
  The public policy records Google's statement that the source IP is discarded before the event
  is logged.
- Photos, submitted text, and other user content are processed only for the feature the user
  invokes, including review-first AI workflows after explicit consent.
- Product interaction analytics exclude account identifiers and nutrition, body, HealthKit,
  workout, location, barcode, and free-form content parameters. Keep the published linked/not-
  linked answer conservative unless a new SDK audit supports changing it.
- Firebase Crashlytics and performance diagnostics are declared separately from account-linked
  app data.
- No listed data type is used for third-party advertising, the developer's advertising or
  marketing, or cross-company tracking.

## Submission Check

1. Compare the current App Store Connect answers with this table, the public policy, the signed
   archive's privacy manifests, and the installed SDK versions.
2. Confirm **Tracking** remains `No`, the app still contains no App Tracking Transparency request,
   and no advertising or cross-app attribution feature has been configured.
3. Confirm health, fitness, location, user content, and identifiers are limited to App
   Functionality, Analytics, or Diagnostics purposes that the app actually uses.
4. Confirm the public Privacy Policy and Support URLs load while signed out.
5. Publish any questionnaire change before submitting the version for review and retain a dated
   screenshot of the resulting product-page preview with the release evidence.
