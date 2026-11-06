# Fload Attribution for iOS

Counts your app's installs in Fload and attributes them to Apple Ads through
Apple's AdServices API. No IDFA, no App Tracking Transparency prompt, no
third-party dependencies. iOS 15+.

## Install

Swift Package Manager. In Xcode: File > Add Package Dependencies, enter
`https://github.com/fload-ai/fload-attribution-ios.git`, choose "Up to Next
Major Version" from `1.0.0`, and add the `FloadAttribution` product to your app
target.

In a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/fload-ai/fload-attribution-ios.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "FloadAttribution", package: "fload-attribution-ios"),
        ]
    ),
]
```

## Use

```swift
import FloadAttribution

// Once, early in launch (didFinishLaunching or your App's init):
Fload.configure(key: "fload_pk_…")

// Optional: link your user id (e.g. RevenueCat's appUserID) to the install.
Fload.setUserId(Purchases.shared.appUserID)
```

The key is your app's public write key from Fload. It can only report
installs for that one app, so it is safe to ship in the binary.

### Objective-C

`FLDAttribution` is the same API for Objective-C, and for bridges that only
see the Objective-C runtime (.NET, Unity `.mm` plugins, React Native, Kotlin/Native):

```objc
@import FloadAttribution;

[FLDAttribution configureWithKey:@"fload_pk_…"];
// or, for tests: [FLDAttribution configureWithKey:key endpoint:@"http://localhost:3001" logLevel:FLDLogLevelDebug];
[FLDAttribution setUserId:appUserId];
NSString *reference = FLDAttribution.installReference;   // nil before configure
```

The class and selector names are a public contract and stay stable.

## What it does

- On the first launch with the SDK, makes a random install reference and
  reports the install once: bundle id, app version and build, OS version,
  device model, locale, first-launch time, and Apple's AdServices
  attribution token (`AAAttribution.attributionToken()`). Fload swaps the
  token with Apple for the attribution record server side.
- `setUserId` sends your user id with the install, or afterwards in a
  separate request. Each id is sent once.
- Everything waits in a small file queue (Application Support, excluded from
  backups) until Fload accepts it. The queue survives relaunches and
  network loss. It retries with exponential backoff and jitter (2 s doubling
  to 6 h), follows `Retry-After` on 429, and gives up after 30 days.
  Requests are idempotent: a retry repeats the same ids.
- It sends when configured, when the app returns to the foreground and when
  the network comes back. All work runs off the main thread.
- A key Fload does not know (HTTP 401) keeps the queue: the SDK logs
  "Fload: ingest key refused" once a launch, tries the key again every 24
  hours, and sends at once when the app is configured with a different key.
- A revoked key (HTTP 410) stops the SDK for good until the app ships a new key.

It logs to the unified log (subsystem `com.fload.attribution`) at `.warning`
and above by default. It never logs the key, the token or the user id.
`FloadOptions(logLevel: .debug)` turns on more.

## Notes

- **Existing users:** the first launch of an app version with the SDK
  counts as an install, for existing users too. Apple's token tells Fload
  whether that device's install came from Apple Ads.
- **Reinstalls** and devices restored from a backup are new installs.
- The **Simulator** has no AdServices token: Apple answers
  `platformNotSupported`, so installs from it arrive as `unsupported_os`
  (seen on the iOS 26.4 simulator).

## Privacy

`PrivacyInfo.xcprivacy` ships with the package: no tracking, no tracking
domains, no required-reason APIs. Collected, linked to the user, not used for
tracking, for analytics: a device ID (the random install reference),
advertising data (the AdServices token) and a user ID (only when you call
`setUserId`). Declare the same in your App Store privacy answers.

## Testing against your own API

```swift
Fload.configure(key: key, options: FloadOptions(endpoint: URL(string: "http://localhost:3001")!, logLevel: .debug))
```

Unit tests: `xcodebuild test -scheme FloadAttribution -destination 'platform=iOS Simulator,name=iPhone 17'`.
The end-to-end test runs only against a local API, when
`TEST_RUNNER_FLOAD_E2E_ENDPOINT` and `TEST_RUNNER_FLOAD_E2E_KEY` are set.

## License

License: MIT. See [LICENSE](LICENSE).
