# Baymo Doctor

Native Mac app for the doctor dashboard. The Xcode target is still `dr-dash`. The Dock and Finder name is Baymo Doctor, and the bundle id is `com.baymo.doctor`.

## Requirements

- macOS with **Xcode 27.2 or newer**.
- **XcodeGen 2.46.0 or newer**.
- [Homebrew](https://brew.sh) for the installation command below, or install XcodeGen using its [official instructions](https://github.com/yonaskolb/XcodeGen#installing).
- An Apple account and development signing team **only when you need a signed local build**. The check below builds with signing disabled.

There are no external Swift package dependencies. XcodeGen generates the project; it does not install Xcode, certificates, or provisioning profiles.

## 1. Generate the project

```sh
cd dr-dash
brew install xcodegen
xcodegen --version
xcodebuild -version
./scripts/generate-project.sh
open dr-dash.xcodeproj
```

If an older XcodeGen is installed, run `brew upgrade xcodegen`.

The generated `dr-dash.xcodeproj` and shared scheme can be committed, so the project can be opened without installing XcodeGen. Regeneration is required after changes to `project.yml` or after adding or removing source files.

## 2. Run on this Mac

1. In Xcode, choose the **dr-dash** scheme.
2. Choose **My Mac**.
3. Press **Run / Cmd+R**.

To check compilation from Terminal without an Apple Team:

```sh
xcodebuild build \
  -project dr-dash.xcodeproj \
  -scheme dr-dash \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/baymo-doctor-build \
  CODE_SIGNING_ALLOWED=NO
```

## 3. Sign with your own team

1. Add your Apple account in **Xcode Settings → Accounts**.
2. Create your local signing configuration:

   ```sh
   cp Configuration/Local.example.xcconfig Configuration/Local.xcconfig
   ```

3. Edit `Configuration/Local.xcconfig`. Set your actual Team ID. Choose a unique bundle-ID prefix if your team cannot register `com.baymo.doctor`:

   ```xcconfig
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   DR_DASH_BUNDLE_ID_PREFIX = com.yourname.baymo
   ```

   Replace both example values. You can find your Team ID in your Apple Developer account's membership details. If you use the shared team and the existing app id, omit the prefix line.

4. Open `dr-dash.xcodeproj`, choose **dr-dash**, choose **My Mac**, and press **Cmd+R**. Xcode uses automatic signing.

`Configuration/Signing.xcconfig` optionally includes `Local.xcconfig`. The app and both test targets inherit the settings. Local settings take effect without regeneration, survive regeneration, and are **ignored by Git**. Never commit your personal signing configuration. Changing the bundle-ID prefix installs a separate app.

## 4. Run tests

In Xcode, choose **dr-dash → Product → Test / Cmd+U**. The shared scheme includes both `dr-dashTests` and `dr-dashUITests`.

From Terminal:

```sh
xcodebuild test \
  -project dr-dash.xcodeproj \
  -scheme dr-dash \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO
```

## Changing project configuration

- **`project.yml`** is the source of truth for targets, source membership, shared build settings, and schemes.
- **`Configuration/Signing.xcconfig`** contains the shared bundle-ID prefix `com.baymo`.
- **`Configuration/Local.xcconfig`** contains optional personal signing overrides and is never committed.
- **`Configuration/dr-dash-Info.plist`** is the app Info.plist. It is empty until a privacy or service key is needed.
- **`Configuration/dr-dash.entitlements`** enables the App Sandbox and read-only access to files the user selects.

Edit the spec, run `./scripts/generate-project.sh`, then commit the spec and generated `.xcodeproj` changes together. Avoid editing shared target settings only in Xcode: regeneration will overwrite those changes.

## Troubleshooting

| Problem | What to check |
|---|---|
| `xcodegen: command not found` | Run `brew install xcodegen` and make sure Homebrew is on your `PATH`. |
| XcodeGen is too old | Run `brew upgrade xcodegen`; minimum supported version is 2.46.0. |
| `xcodebuild` uses Command Line Tools or the wrong Xcode | Open the intended Xcode and select it under Settings → Locations → Command Line Tools. Check `xcodebuild -version` again. |
| Signing team or provisioning error | Set your real `DEVELOPMENT_TEAM` (and a unique `DR_DASH_BUNDLE_ID_PREFIX` if needed) in `Local.xcconfig`, not in Xcode target settings. Check your Apple account in Xcode. If the project still forces another team, run `./scripts/generate-project.sh` to clear hand-edited `project.pbxproj` overrides. |
| New source file is missing from the build | Run `./scripts/generate-project.sh` again. |
