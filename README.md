# Settings Guard

Settings Guard is a free, local macOS friction tool. It requires a long password before allowing **System Settings** to stay open. It does not filter network traffic and does not interfere with iCloud Private Relay.

The app is intentionally a best-effort commitment device, not a security boundary. A root LaunchDaemon checks for the System Settings process four times per second. While the guard is enabled, the daemon immediately terminates it. The Settings window may appear briefly before closing.

## Requirements

- macOS 14 or later
- Xcode installed
- An administrator account for installation

No Apple Developer Program membership is required. The app and daemon are ad-hoc signed locally.

## Upgrade from the PF version

The current installer automatically removes the legacy Friction Blocker PF anchor, its three `/etc/pf.conf` lines, anchor file, and PF enable token. It validates the updated PF configuration and saves a timestamped backup before replacing it.

Your existing long-password verifier is preserved. If the previous app was already configured, the same recovery password becomes the Settings Guard password.

## Build and install

Quit the currently running Friction Blocker app. In Terminal:

```sh
cd "/path/to/FrictionBlocker"
./Scripts/build.sh
sudo ./Scripts/install.sh
open /Applications/FrictionBlocker.app
```

After migration, no Friction Blocker packet-filter rules remain. Private Relay is unaffected by Settings Guard.

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

This removes the app, daemon, launchd job, socket, stored password verifier, and any legacy Friction Blocker PF artifacts.

## Development checks

```sh
xcodebuild -project FrictionBlocker.xcodeproj -scheme FrictionBlocker \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

xcodebuild -project FrictionBlocker.xcodeproj -scheme FrictionBlockerTests \
  -derivedDataPath .build/TestData CODE_SIGNING_ALLOWED=NO test
```
