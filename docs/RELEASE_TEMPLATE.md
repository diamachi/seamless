## macOS installation — unnotarized preview

Open the DMG and drag Seamless into Applications. This preview is not notarized. If macOS blocks the downloaded app and you trust this release, run:

```sh
xattr -dr com.apple.quarantine /Applications/Seamless.app
```

This removes the downloaded-file quarantine attribute from Seamless and its contents. It does not notarize the app or change system-wide Gatekeeper settings. Run it only for the copy you intentionally installed from this repository.
