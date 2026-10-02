# Apple TV storage probe (Q-09)

A diagnostic app with its own bundle identifier and container. It does not read
NPO credentials, contact the backend, or change NPO light's data. It checks a
default SwiftData store, a SwiftData store in `Caches`, and 256 KiB of
`UserDefaults`. Its schema is a single synthetic marker, not ADR 0011's schema.

This is a disposable experiment for [Q-09](../../docs/requirements/open-questions.md#q-09--where-does-local-data-actually-live-on-an-apple-tv),
not a production persistence implementation or a requirement coverage test.
XcodeGen is a development-only prerequisite for this probe; the main app's
project and dependencies are unchanged. Generated projects and build products
stay outside the repository.

## Generate and build

From the repository root, with Xcode and `xcodegen` installed:

```sh
xcodegen generate --spec tools/storage-probe/project.yml --project /tmp/npo-storage-probe
xcodebuild -project /tmp/npo-storage-probe/StorageProbe.xcodeproj \
  -scheme StorageProbe -configuration Debug \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath /tmp/npo-storage-probe-build \
  CODE_SIGNING_ALLOWED=NO build
```

For the paired Apple TV, use your development team and the hardware UDID from
`xcrun devicectl device info details --device Woonkamer`. The device must be awake,
reachable and have Developer Mode enabled. This build can create a development
provisioning profile for the separate probe app:

```sh
xcodebuild -project /tmp/npo-storage-probe/StorageProbe.xcodeproj \
  -scheme StorageProbe -configuration Debug \
  -destination "id=$PROBE_DEVICE_UDID" \
  -derivedDataPath /tmp/npo-storage-probe-device \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$PROBE_TEAM_ID" build
xcrun devicectl device install app --device Woonkamer \
  /tmp/npo-storage-probe-device/Build/Products/Debug-appletvos/StorageProbe.app
xcrun devicectl device process launch --device Woonkamer --console \
  com.bearduck.NPOLightStorageProbe --write
```

The report appears on the TV and in the console. Save it before detaching.
`--write` creates the marker if absent and writes the defaults payload. All
other launches are read-only at the record level: opening SwiftData can still
create an empty store if its file is missing, but the missing marker is reported
and never reinserted. A read-only PASS therefore requires a prior write.

## Hardware checklist

1. Record the device model, tvOS version, probe revision and first write report.
   Each store reports PASS, missing/mismatched data, or the error domain and code.
   A failure of the default store on hardware is an expected possible finding,
   not a reason to skip the cache/defaults checks.
2. Leave the app open for at least ten seconds after writing. Defaults writes
   are asynchronous; an immediate same-process PASS is not durability evidence.
3. Terminate the probe, then launch it without `--write`:

   ```sh
   xcrun devicectl device process launch --device Woonkamer --console \
     --terminate-existing com.bearduck.NPOLightStorageProbe --read
   ```

4. Restart the Apple TV when convenient. Launch the probe with `--read` again,
   without reinstalling it or issuing another write. Record the full report.
5. Add the observations and their limits to Q-09. Relaunch and reboot success
   does not prove resistance to system cache eviction or arbitrary power loss.
   Do not mark NFR-REL-04 implemented on the strength of this experiment.

Apple documents a warning at 512 KB of defaults and termination at 1 MB. This
probe stays below the warning threshold in its own fresh container; it does not
attempt to discover the ceiling by crashing. Never enlarge the payload to 1 MB.
See [Apple's size-limit documentation](https://developer.apple.com/documentation/foundation/userdefaults/sizelimitexceededmessage).

## Validation on 2026-09-20

The probe compiled for the tvOS 26.2 simulator with compiler warnings treated
as errors and passed the repository's strict SwiftLint rules. A fresh read-only
launch reported missing data for all three stores. A write launch passed for
all three, and a subsequent termination and read-only relaunch recovered the
two markers and the complete 256 KiB defaults payload.

Xcode's separate metadata extraction tool emitted:
`warning: Metadata extraction skipped. No AppIntents.framework dependency found.`
The build succeeded, but this is not a warning-free build log. No warning was
suppressed and no unused framework was added to hide it.

Hardware execution and reboot verification remain pending at the owner's
request. The simulator observations do not close Q-09.

When evidence is recorded, remove **NPO Storage Probe** from the Apple TV. That
deletes only this experiment's data. A later experiment can begin with a fresh
install; do not reinstall between the write and read phases.
