# Settings Guard

Settings Guard is a free, local macOS friction tool. It requires a long password before allowing **System Settings** to stay open. Lockdown also closes a user-selected list of macOS apps while the guard is enabled. It does not filter network traffic and does not interfere with iCloud Private Relay.

A good way to use FrictionBlocker is to block websites in Safari with Screen Time, then enable FrictionBlocker to keep System Settings from opening and make those restrictions harder to change impulsively.

The app is intentionally a best-effort commitment device, not a security boundary. A root LaunchDaemon checks for the System Settings process four times per second. While the guard is enabled, the daemon immediately terminates it. The Settings window may appear briefly before closing.

## Recommended use: block websites in Safari

1. Open **System Settings → Screen Time**, enable Screen Time, and configure its **Content & Privacy** web-content restrictions. Add the websites you want to block to the restricted list. The exact labels vary by macOS version; see [Apple’s guide to web-content restrictions](https://support.apple.com/en-ie/guide/mac-help/mchlbcf0dfe2/mac).
2. Check in **Safari** that your selected websites are blocked.
3. Enable **FrictionBlocker**. While protection is active, it closes **System Settings** when you try to open it, adding friction to turning off Screen Time or changing the website restrictions.

Screen Time handles the website blocking; FrictionBlocker guards access to the settings that control it. Keep Screen Time and its content restrictions enabled. FrictionBlocker’s daily schedule controls its Settings guard and selected apps; it does not turn Screen Time’s website restrictions on or off.

## Requirements

- macOS 14 or later
- Xcode installed
- An administrator account for installation

No Apple Developer Program membership is required. The app and daemon are ad-hoc signed locally.

## Build and install

Quit any currently running Settings Guard app. In Terminal:

```sh
cd "/path/to/FrictionBlocker"
./Scripts/build.sh
sudo ./Scripts/install.sh
open /Applications/FrictionBlocker.app
```

On a fresh installation, the daemon starts with no password configured. Open the app and follow the first-time setup flow to generate and store the Settings Guard password. When reinstalling an already configured copy, the existing password verifier and guard state are preserved.

The installer replaces the app and daemon, starts the daemon automatically, and does not affect iCloud Private Relay.

## How it works

- The root daemon starts automatically at boot.
- A random 24-character password is generated during first-time setup; passwords shorter than 20 characters are rejected.
- Only a salted PBKDF2-HMAC-SHA256 verifier is stored. The plaintext password is not saved.
- With the guard active, the daemon polls the process list every 250 milliseconds and kills System Settings or a selected Lockdown app if it appears.
- Disable the guard with the password to choose apps from the searchable in-app list, then enable it again. Use **Add Apps** for apps outside the usual Applications folders. The selection survives reboot.
- A correct password disables the guard and its daily schedule with no timer.
- Re-enabling the guard is immediate and does not require the password.
- Failed password attempts use an exponential cooldown capped at five minutes.
- The manual state and daily schedule survive app closure, logout, and reboot.

## Daily schedule

Protection defaults to **10 p.m.–6 a.m. every day** in the Mac’s local time zone.
The root daemon computes protection from the current wall clock, so it works
with the app closed and catches up after sleep, restart, or time-zone changes.
The Mac is not woken from sleep solely to enforce protection.
Start is inclusive and end is exclusive. Customize the start and end times in
**Daily schedule**, then click **Save Schedule**. Equal times are rejected.
Existing installations adopt the nightly schedule on this upgrade; the password
and selected apps are preserved. Outside the window, protection is off.

A password unlock disables protection **and the schedule** until you enable it
again. Turn the schedule back on after editing apps or times. Manually enabling
protection also switches to manual mode, keeping protection on until a password
unlock. This schedule controls FrictionBlocker’s System Settings guard and
selected apps; it does not toggle Apple Screen Time’s Content & Privacy switch.

## QR code and barcode unlocking

Unlock with your password, then choose **QR or barcode unlock → Set Up Code…**.
Use **Scan a QR Code or Barcode…** to scan an existing code on a book, product,
card, sign, or another object. Enter your current password and choose
**Use This Code** to enroll it. Nothing needs to be generated or printed.
The camera supports the barcode formats available through Apple's Vision API,
including QR, Code 128, EAN-13, and UPC-E. Show only one code at a time.

While protection is active, **Scan to Unlock…** accepts the same decoded contents
as the enrolled code. It performs exactly the same action as a correct password:
protection and its daily schedule stay disabled until you enable them again.
The password remains available as a fallback. The contents of a scanned code
are never opened as a URL or executed.

Only a salted verifier is stored. Short barcode values are hashed before the
password KDF; password length requirements remain unchanged. Previously enrolled
generated QR codes continue working. Use **Replace Code…** or
**Remove Code Unlocking**, authenticated with your password, to change the code.
Replacement invalidates the previous code. Wrong scans and passwords share
the same persisted cooldown. Passwords, app lists, and schedules are preserved.

Camera access is requested only when scanning. Frames are processed on the Mac,
not recorded or uploaded. Capture stops when scanning ends, is cancelled, or
the app becomes inactive. If access is denied, unlock with your password and
allow the camera in System Settings → Privacy & Security → Camera.

## Limitations

- System Settings or a selected app can flash on screen before the daemon closes it.
- Lockdown closes the selected macOS app. It does not block its website in a browser or helper processes with different executable paths.
- Some settings can be changed using Terminal commands without opening System Settings.
- An administrator can stop the daemon, uninstall it, or bypass it from Recovery mode.
- This does not protect settings contained inside other apps, such as Safari's own Extensions settings.
- The free, race-free alternative would require Apple's restricted Endpoint Security entitlement and a system extension.

Do not disable System Integrity Protection to strengthen this app. Settings Guard intentionally leaves macOS system protections intact.

## Uninstall

```sh
cd "/path/to/FrictionBlocker"
sudo ./Scripts/uninstall.sh --confirm-remove
```

This removes the app, daemon, launchd job, socket, and stored password verifier.

## Development checks

```sh
xcodebuild -project FrictionBlocker.xcodeproj -scheme FrictionBlocker \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

xcodebuild -project FrictionBlocker.xcodeproj -scheme FrictionBlockerTests \
  -derivedDataPath .build/TestData CODE_SIGNING_ALLOWED=NO test
```
