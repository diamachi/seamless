# LinkMyMac reference review

Reviewed 2026-11-02. Official documentation/store review only; no installation, source inspection, or physical-device validation.

## Findings

LinkMyMac is a closer reference for our debugging-off baseline than AirSync. Its Google Play listing explicitly advertises no Developer Mode and discloses AccessibilityService for user-initiated taps, scrolling and navigation. Its help center describes screen-sharing confirmation through Android's official screen capture API. Together these support investigating MediaProjection plus opt-in accessibility as a first-class screen-control approach, without assuming unrestricted control.

The official help center also says automatic Android-to-Mac clipboard sync may require its accessibility service on recent Android/Samsung devices. This is a product claim, not evidence that an arbitrary accessibility service has general clipboard-read permission. Exact implementation, device compatibility, focus behavior and image/text support remain unverified. There is a documentation inconsistency: Google Play describes accessibility as solely for remote control, while help mentions it for clipboard sync. Resolve behavior through device tests before adopting an equivalent design.

The developer distinguishes Standard and Advanced Mirroring. Advanced mode adds higher quality, phone audio, screen-off operation and supported app windows. Release notes mention Wireless Debugging fixes, but reviewed documentation does not map every advanced capability to its permission/transport requirements. Do not promise all advanced features work with debugging off.

Documented features include bidirectional files, phone notifications and supported replies, clipboard, phone battery/status (developer release notes), screen/control, virtual webcam and microphone. The webcam guide describes a registered Mac camera extension, front/back selection, flash and frame-rate controls. Hotspot automation and Find My Phone were not established in the reviewed pages.

## Architecture implications

- Elevate MediaProjection plus optional accessibility control from a fallback to the leading feasibility candidate for the user's debugging-off workflow.
- Test ordinary screen control and automatic clipboard separately; neither proves the other works on our phone.
- Keep advanced ADB features optional with explicit capability reporting.
- Banking compatibility remains a separate physical-device check even with Developer Options off; accessibility-service policies may vary by app.
- This is a behavioral reference. No code reuse/license or security-audit conclusion is established.

## Sources

- Play listing and accessibility disclosure: https://play.google.com/store/apps/details?id=com.kdg.beam_android
- Help and clipboard permission guidance: https://linkmymac.com/help/
- Feature guide: https://linkmymac.com/features-guide
- Webcam guide: https://linkmymac.com/android-webcam-for-mac
- Clipboard guide: https://linkmymac.com/android-clipboard-on-mac
- Developer's Standard/Advanced distinction: https://buttondown.com/linkmymac/archive/linkmymac-156-is-here-my-biggest-update-yet/
