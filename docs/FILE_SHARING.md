# File sharing and storage browsing

## Transport and trust

Modern companions advertise `bulkVersion: 1`. Metadata/acceptance/cancellation use the control session; binary bytes use a separate certificate-pinned TLS connection to the Android listener. Each random transfer ID is bound to its peer, direction, expiry and one-time claim. The saved credential and active control session are required. This is a custom paired-device protocol, not LocalSend interoperability.

Sizes must be exact nonnegative JSON integers through 2^53−1 bytes. There is no product size cap, but platform limits, free space and source availability apply. Senders hash the file before offering it; receivers stream and verify SHA-256 before committing the destination. Memory use is bounded. Persistent resume is not implemented, and valid 100 GB metadata is not evidence of a successful physical 100 GB transfer.

Mac incoming data uses a sibling `.part` file, removed on failure. Successful receives use Downloads with unique names by default. Explicit Finder file-promise destinations override Downloads. New phone preferences enable automatic receiving; existing saved choices remain honored. Automatic receiving can be disabled per phone in Settings.

Android 10+ streams incoming files into pending MediaStore Downloads entries and publishes them after verification. Android 7–9 uses a cached file plus explicit Save fallback. Incoming phone acceptance and per-trusted-Mac auto-accept policies remain separate from macOS receiving preferences.

## Android sending

Overview offers **Send files** using OpenMultipleDocuments and **Send folder as ZIP** using OpenDocumentTree. Exactly one authenticated Mac must be connected. External ACTION_SEND/ACTION_SEND_MULTIPLE selections enter the same queue after the explicit Send action.

BulkExchange prepares/hashes one queued outgoing source at a time, then advances after completion or cancellation. It respects the shared eight-active-entry limit. The queue is in-memory and loses pending work on process death. URI access must remain available until the queued transfer reads it.

FolderArchive walks only the explicitly selected tree. It validates names, rejects cycles/excessive depth and writes ZIP entries with bounded buffers. Subfolder paths and empty directories are preserved. Preparation requires free cache storage and uses an indeterminate in-app bar. Temporary ZIPs are removed after transfer/cancellation; the Mac does not automatically extract them.

In-app progress includes per-transfer bytes/bars and outgoing file count. OS notifications are terminal results only; repeated progress notifications were removed in 0.6.4. Android “Sent to Mac” reports bytes written, while the Mac's completion follows its checksum and final destination commit. Declining notification permission does not block file transfer.

## Browsing and media

Optional Android All files access permits shared storage and MediaStore browsing, not private app data. Selected read-only document-tree/media grants provide narrower alternatives. Mac receives peer/session-scoped opaque tokens; remote callers cannot supply arbitrary raw paths or URIs. Tokens are cleared on disconnect or revocation.

Listings are paged at 100 items, with bounded token maps and thumbnail workers. Shared-storage canonical paths stay within the authorized root. Browsing is read/download-only, with no remote delete, rename, execute or arbitrary writes. Removable volumes use the selected-folder flow.

Mac Files combines storage navigation and transfer drop targets. Photos provides a media grid and selected-item downloads. FolderDownloads recursively enumerates authorized tokens, creates a new Downloads tree without merging existing folders, and queues regular files through the verified bulk path. Depth/count limits and deadlines bound provider responses. Enumeration errors are explicit; already queued downloads may continue.

## Mac surfaces and lifecycle

Window/menu-bar drops accept regular file URLs and pin the chosen phone at drop time. Mac outgoing directory packaging is not implemented; Android folder sending is a separate ZIP path. IncomingFileDragHandle uses Finder file promises and completes once, including cancellation/errors. Received local files can be dragged out by URL.

ActivityPopup shows live progress and pending offers. Notifications go through MacNotificationDelivery after verified results. Focus/display-sharing settings can suppress visible banners independently of app delivery.

Waiting offers expire after five minutes. Mac active idle deadlines refresh on progress; Android uses socket idle timeouts. Cancellation closes the owned data socket and removes partial/temporary data. Disconnect cleans only the affected peer. The legacy 20 MiB/base64 transport remains available only for older-companion compatibility.

## Validation

Generated 32 MiB transfers have passed both directions with checksum comparison. Android multi-file/folder workflow was reported working; a broad provider/folder corpus and interruption/large-file campaigns remain pending. Automated checks cover split/coalesced framing, checksum rejection, peer isolation, large metadata and folder-tree constraints. See [VALIDATION.md](VALIDATION.md).

Android share-sheet flow (0.6.11): Share file(s) → Seamless queues directly to a single connected Mac. With several connected Macs, choose the destination; offline, reconnect or cancel. Pending external URI grants remain in memory and are not restored after process death. Folder as ZIP is in Overview → Share with your Mac. Setup now exposes automatic Downloads consent on both devices; transfer progress remains in-app and terminal notifications remain enabled, without repeated OS progress alerts.
