# Settings Guard

Settings Guard is a free, local macOS friction tool. It requires a long password before allowing **System Settings** to stay open. It does not filter network traffic and does not interfere with iCloud Private Relay.

It can be useful alongside Screen Time: configure Screen Time content blockers or other limits, then use Settings Guard to add friction to changing those settings. This can help reduce impulsive screen-time changes and make it easier to stick to your limits.

The app is intentionally a best-effort commitment device, not a security boundary. A root LaunchDaemon checks for the System Settings process four times per second. While the guard is enabled, the daemon immediately terminates it. The Settings window may appear briefly before closing.

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
- With the guard active, the daemon polls the process list every 250 milliseconds and kills System Settings if it appears.
- A correct password disables the guard with no timer.
- Re-enabling the guard is immediate and does not require the password.
- Failed password attempts use an exponential cooldown capped at five minutes.
- The enabled or disabled state survives app closure, logout, and reboot.

## Limitations

- System Settings can flash on screen before the daemon closes it.
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
