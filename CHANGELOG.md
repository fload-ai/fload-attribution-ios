# Changelog

## 1.2.0

- The install says when the app was first installed on the device:
  `originalInstallAt`, the creation date of the app's Documents directory,
  which an update keeps (FLO-4496). An existing user's first launch of the
  first build with the SDK is an install too; with this, Fload counts those
  users apart from new downloads. Left out when it cannot be read. Fload
  servers before FLO-4496 ignore it.
- The privacy manifest declares one required-reason API for it: a file
  timestamp inside the app's own container (`C617.1`).
- No API change.

## 1.1.0

- `FloadOptions.wrapper` (`FloadWrapper(name:version:)`): a cross-platform
  wrapper (Flutter, React Native, Capacitor, Cordova, Unity, .NET, KMP)
  names itself, and every request carries it as `sdk.wrapper`. Objective-C
  bridges use `configureWithKey:endpoint:logLevel:wrapperName:wrapperVersion:`.
  Apps calling the SDK directly change nothing (FLO-3957). A name or version
  over 64 characters is left out rather than risk the request.
- Identify requests also carry `sdk`, so an install Fload first hears of
  through an identify still knows its SDK. Older Fload servers ignore it.

## 1.0.2

- Installs report `sdk.version` `1.0.2`. 1.0.0 reported `0.1.0`. The
  version now comes from `VERSION`; a test holds `Fload.sdkVersion` to it,
  and CI holds a tag to it.
- `FLDAttribution` and `FLDLogLevel`: the API for Objective-C and for bridges
  (.NET, Unity, React Native, Kotlin/Native). No change to the Swift API.
- README: the Simulator reports `unsupported_os`, not `token_error`.

## 1.0.0

- First release.
