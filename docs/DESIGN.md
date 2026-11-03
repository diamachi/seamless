# Seamless interface design

Updated 2026-11-03. Current UI development: 0.6.7. Earlier design notes below are historical where superseded by the current refinements.

## Direction and references

The design targets an O+ Connect-style flat phone preview with the phone's wallpaper, cards, a coherent palette, generous sidebar padding, and comfortable Light/Dark modes. NectarLink is now the main dashboard reference; the supplied O+ Connect screenshot remains the phone-preview composition reference: a separate phone illustration panel, adjacent device details, quiet surfaces and clear actions. It is a visual reference, not proof that its system integration is available to an ordinary third-party Android companion.

Other references reviewed: OPPO Connect's official website (https://connect.oppo.com/) for restrained surfaces/cards, an O+ Connect desktop screenshot published on OnePlus Community (https://community.oneplus.com/thread/1883956642727329801), and Microsoft's Phone Link wallpaper documentation (https://support.microsoft.com/en-us/windows/apps/phonelink/additional-features-and-settings-in-phone-link). No third-party wallpaper or brand asset is bundled in Seamless.

## Palette

`InterfacePalette.swift` owns semantic colors, resolved against SwiftUI's color scheme. Avoid hard-coded page-specific grays; use these tokens when expanding the interface.

| Role | Light | Dark |
| --- | --- | --- |
| Canvas | #F7F5EF | #1D1C1A |
| Sidebar | #F0ECE3 | #24221F |
| Card surface | #FFFDFA | #2B2824 |
| Raised panel | #F4EDDE | #342F28 |
| Accent | #8C5C25 | #E6BC7A |
| Accent background | #F1E4CD | #403529 |
| Primary text | #302D27 | #EEE9DF |
| Secondary text | #777166 | #B7B0A3 |
| Border | #E4DED2 | #423D35 |

Use one restrained accent for actions/selection, with text labels for status. Native text fields, menus and forms retain platform behavior. `WorkspaceCard` supplies a shared 20-point radius, 22-point padding and quiet border. Default page inset is 32 points, with 24-point gaps between major sections. SF Symbols and system typography keep the UI familiar; rounded headings add a small amount of character.

## Layout and appearance

`MainWindow` uses custom sidebar buttons rather than dense default List rows. Sidebar content has 18-point horizontal padding; rows have 12-point vertical padding, 12-point icon/text spacing, and rounded selected states. Workspace navigation and device management are separate groups. The phone switcher is a compact inset card. `AppearanceSelector` sits at the bottom with System, Light and Dark controls; its setting is saved globally, independently of phone selection. `AppPreferences` decodes older settings without an appearance key as System.

Overview has a split device card: `PhoneOverviewCard` places `PhoneIllustration` on a softly tinted panel and the real phone name, Android version, battery state and screen-sharing action beside it. A details card sits below it, with a compact action column alongside it on wider windows. Narrower windows stack these columns vertically. This borrows NectarLink’s compact card composition while preserving the O+ Connect-style phone panel. Scrollable pages handle reduced window height. The illustration is decorative and never masquerades as a live stream; live video stays in Phone screen.

## Wallpaper behavior

`PhoneIllustration` renders a selected wallpaper inside a flat Android-style frame, with a small punch-hole camera and gesture handle. Without a chosen image it displays an original SwiftUI-drawn abstract sample; the UI invites the user to choose the same image as the phone.

`PhoneWallpaperStore` imports an explicitly chosen local image (20 MiB maximum), uses ImageIO to normalize orientation and downsample to 1,200 pixels, and stores only a compressed preview in Application Support/Seamless/Wallpapers. A SHA-256-derived filename binds the preview to the stable phone identity without accepting arbitrary path components. The original image is never modified. Reset or unpair removes only Seamless's copy. Wallpaper images remain local and are not sent across the connection.


## Verification

Automated coverage checks appearance persistence/legacy defaults and per-phone wallpaper import, reload and reset while preserving the original image. Native visual checks must cover Light, Dark, smaller windows, selected/offline phones and the image picker. Record completed checks in VALIDATION.md; a placeholder preview is not evidence of real phone-wallpaper synchronization.

The full NectarLink feature and debugging-off compatibility review is in `NECTARLINK_REVIEW.md`. It distinguishes documented product claims, source evidence and engineering proposals. Device details display actual processor identifiers, Android/recognizable build OS name, RAM and internal storage use; no dummy specifications appear while waiting for the updated companion.

## 0.3.2 refinement

Use the available content width; let dashboard columns stack when constrained. Remove the contrasting titled toolbar chrome with the native hidden-title-bar window style. Keep the traffic lights and sidebar affordance. Use a shared rounded tonal button style, including distinct primary and secondary actions. Notifications have separate Inbox/App settings destinations within the workspace, spaced cards, actual companion-provided icons with initial fallbacks, and an adaptive app grid. Do not mix settings rows with notification messages in a system List.

## Dashboard refinements

Appearance lives in Settings. Use a single prominent connection indicator in the main workspace header; the sidebar's secondary text is battery/device context, not a second connection badge. Allow wider sidebar sizing and wrapped custom names. Main page actions belong on the right with prominent fill and clear text. Overview is compact with hardware details, a ring/stop toggle and five original vector color variants. No user wallpaper picker is exposed. Screen sharing uses an apps column and constrained phone mockup with controls/popout, and a small frame-rate selector in the top-right. Files combines storage and transfer panels; Photos is a separate zoomable selectable media grid. Clipboard is a session shelf plus right-side composer. Live camera puts quality/controls beside a compact preview and Stop below it. Devices shows selection and rename explicitly. Android uses the same palette and moves diagnostics to Settings.

## Current 0.6 refinements

Appearance is in Settings; the Dock mark remains dark pastel. Overview keeps device details and Files/Photos/Live camera/Calls as separate cards, alongside a compact phone/ringer summary and aligned clipboard cards. Calls selectors use the shared palette-based popover control. Mac setup uses a compact sheet with an accent-colored progress strip and optional per-feature permission actions. Android shares the warm paper/charcoal palette, quiet 20dp cards and generous spacing; Overview shows connection and Mac details, with permission/setup controls in a separate flow. The MacBook illustration is original vector drawing, with restrained CPU/RAM/storage details rather than the dense About This Mac panel. Automatic phone-wallpaper access is still unimplemented; the current phone illustration uses preset color variants, superseding the older choose-wallpaper affordance described above.

Phone previews use built-in color variants. Automatic phone wallpaper extraction is not implemented. Devices puts Wi-Fi pairing first with numbered steps, followed by saved phones and optional USB transport. The sidebar Connect new phone action opens that page directly.
