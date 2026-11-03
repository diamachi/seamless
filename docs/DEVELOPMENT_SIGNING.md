# Development signing and Keychain trust

`scripts/build-macos.sh` reads `SEAMLESS_SIGNING_IDENTITY`, then an optional local `.tools/signing-identity` file, and otherwise uses ad-hoc signing. The local file contains a certificate fingerprint and is excluded from source distribution. Never commit signing identities, private keys, provisioning profiles or credentials.

A stable signing identity helps macOS recognize successive builds. Ad-hoc rebuilding changes the designated requirement and may trigger new Keychain approval for `dev.seamless.mac.phone-credentials`. When appropriate, review the prompt locally and choose **Always Allow** for Seamless; never share your Mac password. Changing signing identity or distribution channel can require new approval. Credentials stay in Keychain; no allow-all-applications ACL is used.

```sh
codesign -d -r- dist/Seamless.app
codesign --verify --deep --strict dist/Seamless.app
```

`scripts/package-macos.sh` creates an ad-hoc-signed test copy, leaving the development app unchanged and excluding its signing certificate. The DMG is not notarized. Public Developer ID signing/notarization and a standalone camera extension remain release work.

## Android distribution key (0.6.12 onward)

The owner approved a dedicated Android distribution identity and storing it in encrypted Actions secrets for diamachi/seamless. The public certificate SHA-256 is in `android/signing-certificate.sha256`. The private PKCS12 keystore is local under `.tools/android-signing/seamless-release.p12`; `.tools/android-signing.properties` supplies its path, alias and passwords. Both have owner-only file permissions and are ignored by Git. Back up both to protected storage outside this checkout; losing the key prevents signing compatible updates. Never put either file in source, an issue, release asset or public log.

GitHub Actions secrets hold the same keystore (base64 transport encoding) and passwords; base64 is not encryption itself. GitHub encrypts stored secrets. Authorized repository administrators and trusted main workflow execution can access these values. Pull-request builds receive no signing secrets. Main builds restore into a temporary file, verify the signer, then delete it. No automatic Android Play Store enrollment or upload is involved.

The existing debug-signed APK cannot generally be updated with the new distribution key. One final reinstall may be necessary; uninstalling clears app data and requires pairing/permissions again. Do not uninstall a personal phone through automation. Subsequent distribution builds use the same key and increasing version codes. Keep debug and signed-distribution installers separate when testing.
