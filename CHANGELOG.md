# Changelog

## 1.0.2

- Installs report `sdk.version` `1.0.2`. 1.0.0 reported `0.1.0`. The
  version now comes from `VERSION`; a test holds `Fload.sdkVersion` to it,
  and CI holds a tag to it.
- `FLDAttribution` and `FLDLogLevel`: the API for Objective-C and for bridges
  (.NET, Unity, React Native, Kotlin/Native). No change to the Swift API.
- README: the Simulator reports `unsupported_os`, not `token_error`.

## 1.0.0

- First release.
