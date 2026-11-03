# Development signing and Keychain trust

`scripts/build-macos.sh` reads `SEAMLESS_SIGNING_IDENTITY`, then an optional local `.tools/signing-identity` file, and otherwise uses ad-hoc signing. The local file contains a certificate fingerprint and is excluded from source distribution. Never commit signing identities, private keys, provisioning profiles or credentials.

A stable signing identity helps macOS recognize successive builds. Ad-hoc rebuilding changes the designated requirement and may trigger new Keychain approval for `dev.seamless.mac.phone-credentials`. When appropriate, review the prompt locally and choose **Always Allow** for Seamless; never share your Mac password. Changing signing identity or distribution channel can require new approval. Credentials stay in Keychain; no allow-all-applications ACL is used.

```sh
codesign -d -r- dist/Seamless.app
codesign --verify --deep --strict dist/Seamless.app
```

`scripts/package-macos.sh` creates an ad-hoc-signed test copy, leaving the development app unchanged and excluding its signing certificate. The DMG is not notarized. Public Developer ID signing/notarization and a standalone camera extension remain release work.
