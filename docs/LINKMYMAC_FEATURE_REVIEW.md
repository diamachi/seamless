# LinkMyMac feature feasibility

Reference screenshot reviewed2026-11-02, excluding Google Messages. Proposals below are not implemented behavior.

| Feature | Feasibility and dependency |
| --- | --- |
| Notification filters and quieter mirroring controls | Feasible in default debugging-free mode; basic per-app filters already implemented. Further grouping/quiet controls need design and tests. |
| Lower battery/background activity | Feasible through event-driven updates, backoff and idle work reduction; battery savings must be measured. |
| Native ADB advanced mirroring | Feasible as a separate opt-in backend, never a requirement for the existing features. No ADB session was started for this review. |
| Individual Android app windows | Feasible with shell/ADB-backed virtual displays and app launch; per-app and device compatibility testing required. Current MediaProjection path cannot preselect arbitrary capture apps. |
| Screen-off mirroring | Supported by scrcpy's privileged backend on compatible devices; different from locking the phone or bypassing protected app content. |
| Duo Mode | Term alone is ambiguous. If it means independent phone use plus apps on a Mac virtual display, feasible with the advanced backend, subject to task/app behavior. |
| Faster/resumable transfers | Feasible; current encrypted binary streaming has no fixed product byte cap but no resume. Recovery/checkpoint work remains. |
| Connection dashboard/guided recovery | Feasible; build on existing authenticated reconnect/status, never weaken certificate checks or silently reset trust. |
| Foldable transitions | Feasible through dynamic capture size/rotation handling; requires foldable hardware validation. |
| Cast photos/videos/audio | Feasible for user-selected accessible media. DRM/provider/app capture restrictions still apply. Current file/gallery access is not a complete cast receiver. |
| Side-by-side chat layouts | Feasible as layout; each messaging provider needs an authorized integration or notification replies. Excluding Google Messages does not grant access to other private chat histories. |
| Privacy-conscious diagnostics | Feasible with bounded, opt-in, redacted session diagnostics, not clipboard/message/file contents. |

The screenshot's Native ADB item is evidence of a different advanced feature path, not evidence that standard Android capture permits phone-side consent to be skipped. LinkMyMac App Store description explicitly separates Standard Mirroring and Advanced Mirroring, listing individual app windows and screen-off support under Advanced. Its help still describes screen confirmation for official capture. Exact proprietary implementation is unverified.

Normal scrcpy transport uses ADB during a session; a permanent one-time grant followed by debugging off cannot be promised. Privileged helper persistence across toggles/reboot is a separate unverified design and must not be represented as working. Respect user's default debugging-off preference.

Sources:
- https://apps.apple.com/us/app/linkmymac/id6755784154?platform=mac
- https://linkmymac.com/help/
- https://github.com/Genymobile/scrcpy/blob/master/doc/virtual-display.md
- https://github.com/Genymobile/scrcpy/blob/master/doc/device.md
- https://github.com/Genymobile/scrcpy/blob/master/doc/connection.md
