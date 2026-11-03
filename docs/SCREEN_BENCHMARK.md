# Debugging-free screen encoding test

## What this measures

The Android app uses the real MediaProjection -> hardware MediaCodec Surface pipeline. Encoded H.264 output buffers are counted and released. No frames are recorded, transmitted or logged. This measures capture/encoding throughput at a chosen size and requested rate. It cannot measure Wi-Fi transport, Mac decoding/rendering, capture-to-display latency or accessibility input delay.

On API 29+, Android 0.1.1-dev sets the explicit Surface input-rate cap as well as the frame-rate hint. API 24-28 are hint-only in this prototype. Debug builds log numeric measurements under `SeamlessBenchmark`; screen pixels, notification content and clipboard content are not logged.

## Test procedure

1. Install the development APK using Android's ordinary package installer. Developer Options can remain off. The app supports installation from API 24 onward; physical results currently cover only the Nothing Phone (1) on Android 17; older-version codec behavior remains unverified.
2. Choose 60 fps and a 1920 px maximum dimension. This preserves aspect ratio; it is not a promise of 1920x1080 output on a portrait phone. Your selection is saved.
3. Start the benchmark. Allow the notification if desired, then approve Android screen sharing. Choose the entire screen to measure changing content in other apps.
4. Scroll a non-sensitive page or run a continuously animated app. Static screens naturally produce fewer encoded frames. Avoid protected content, which Android may exclude.
5. Return to Seamless after a short run. Record the selected encoder, actual encoded size, peak interval fps, session-average fps, bitrate and elapsed time. A peak is not proof of sustained performance. The longest output gap includes static periods and is not a latency measure.
6. Stop through the app, foreground notification or Android's screen-sharing indicator. Results stay in memory until the next run or process exit. No session automatically resumes after reboot/process death.
7. Repeat with 120 fps, then optionally 1280 px to distinguish resolution limits. Unsupported advertised codec combinations produce an explicit error rather than silently lowering the rate.
8. After basic operation works, run a repeatable 15-minute animation workload and note thermal throttling and battery use. The current UI does not export a time series; add that before treating the test as formal sustained-performance acceptance.

The fixed virtual-display output does not yet adapt when rotating the phone or changing the captured app's dimensions. Restart the session after rotating for comparable measurements. Codec metadata is a capability hint, not proof of delivered fps; some vendor codec metadata is inaccurate.

## Next gate

Add authenticated device pairing and an encrypted screen transport, hardware decoding and native rendering on Mac. Instrument timestamps/queue depth and frame pacing. Compare loss/jitter behavior before fixing the transport. Measure input responsiveness separately when accessibility control exists. Only this full pipeline can establish the agreed 60 fps and latency targets.

## Recorded Wi-Fi results

See `VALIDATION.md` and `test-results/` for controlled 60 fps and experimental 120 fps runs. The final 20 encoder intervals averaged 59.27 fps and 116.04 fps respectively. Mac receipt/enqueue counters showed 58 and 118 fps at observed moments. Neither counter measures actual panel presentation or end-to-end latency; these are still acceptance gates alongside longer thermal runs.
