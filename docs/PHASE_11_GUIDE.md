# Phase 11 — Shipping: Windows Build, Installer, Steam and itch.io

This phase turns the project into something players can download: a Windows game with its
own icon and version details, a proper installer, and the files and steps for releasing
on Steam and itch.io.

---

## Part 1 — What's in the project

| File | What it's for |
|---|---|
| `export_presets.cfg` | Two export presets. **Windows Desktop**: 64-bit, the icon, version and company details in the .exe. **Linux**: for testing, and for players on Linux or Steam Deck. Tests, tools and docs are left out of the game. |
| `assets/icon/thief_of_london.ico`, `…_256.png` | The game's icon at every Windows size (16 to 256 px), made from `icon.svg` by `tools/make_icon.gd` |
| `installer/thief_of_london.iss` | The Inno Setup installer script |
| `installer/README.txt`, `LICENSE.txt`, `THIRD_PARTY_NOTICES.txt` | Installed next to the game. The notices are the Godot licence, which the MIT licence requires you to ship, and are made by `tools/make_notices.gd`. |
| `tools/build_windows.bat` | **On Windows:** exports the game and builds the installer in one go |
| `tools/build_release.sh` | **On Linux or macOS (or CI):** exports Windows and Linux, checks the exported game starts, and zips both for itch.io |
| `scripts/core/smoke_test.gd` | The game's own start-up check: any build started with `-- --smoke-test` loads London and the hills and reports `SMOKE OK` |
| `tools/set_version.sh` | Sets the version everywhere it's written (game, .exe, installer) |
| `tools/steam/*` | Steam upload scripts (SteamPipe) |
| `tools/publish_itch.sh` | itch.io upload with butler |

The game saves to `%APPDATA%\ThiefOfLondon` (saves and settings). The installer and the
uninstaller know this: uninstalling asks before deleting saves.

## Part 2 — One-time setup (Windows)

1. **Godot 4.7.2.** Open the project. Then:
   1. Go to **Editor → Manage Export Templates → Download and Install**.
   2. Wait for about 1.3 GB to download.
2. **Inno Setup 6.** Download it from <https://jrsoftware.org/isdl.php> and install with the defaults.
3. **(Optional) A code-signing certificate:** see Part 7.

## Part 3 — Building the game

**The quick way (Windows):** open a Command Prompt in the project folder and run:

```bat
tools\build_windows.bat "C:\Path\To\Godot_v4.7.2-stable_win64.exe"
```

You get:
- `builds\windows\TheThiefOfLondon.exe` and `TheThiefOfLondon.pck`: the game. Keep the two files together.
- `builds\windows\TheThiefOfLondon.console.exe`: the same game, with a console window for error messages.
- `installer\Output\TheThiefOfLondon-0.11.0-Setup.exe`: **the installer**.

**From the editor:**
1. Go to **Project → Export… → Windows Desktop → Export Project**.
2. Save it into `builds\windows\` as `TheThiefOfLondon.exe`, with "Export With Debug" unticked.
3. Right-click `installer\thief_of_london.iss` → **Compile**.

**From Linux or macOS** (also works in CI):

```bash
tools/build_release.sh /path/to/godot
```

It exports Windows and Linux, runs the exported Linux game's `--smoke-test` to check it
loads London and the hills, and writes `builds/TheThiefOfLondon-<version>-windows.zip` and `-linux.zip`. Inno Setup
runs only on Windows, so build the installer there.

**Version numbers.** Before a release:

```bash
tools/set_version.sh 0.12.0
```

This updates the title screen, the .exe's properties and the installer. Then rebuild.

## Part 4 — Test the build before you release it

Do this on a PC that has never had Godot on it, if you can:

1. **Install** with the installer, and start the game from the Start menu shortcut.
2. **New Game:** you wake in the hills, and Mission 1 plays.
3. **Save** (Esc → Save Game), quit, and restart. **Continue** loads it.
4. **Settings:** try **Low** and **Ultra**. Rebind a key, restart, and check it stuck.
5. **Travel** to London and back (loading screens, autosave).
6. **Alt+Tab** out and back in (the mouse is recaptured). Try fullscreen and windowed.
7. **F3:** check the frame time on your target minimum PC.
8. **Uninstall.** You're asked about saved games, and the saves are kept unless you say yes.
9. **Safe mode:** the "safe mode, Direct3D 12" shortcut runs (for PCs with poor Vulkan drivers).

## Part 5 — Releasing on Steam

### 1. Join Steamworks

1. Go to <https://partner.steamgames.com>. You pay the app fee (US$100 per game, recoupable) and give tax and bank details.
2. Create the app. Note the **App ID**.
3. Under **SteamPipe → Depots**, note the **depot ID** (usually App ID + 1).
4. Set it to **Windows 64-bit**.

### 2. Store page

The images needed (exact sizes):

| Asset | Size |
|---|---|
| Header capsule | 920 × 430 |
| Small capsule | 462 × 174 |
| Main capsule | 1232 × 706 |
| Vertical capsule | 748 × 896 |
| Page background | 1438 × 810 |
| Library capsule | 600 × 900 |
| Library hero | 3840 × 1240 |
| Library logo | 1280 × 720 (transparent PNG) |
| Screenshots | at least 5, 1920 × 1080 |
| Trailer | recommended |

**Screenshot tips:**
- Press **F12** in the game: it saves the screen without the HUD to `%APPDATA%\ThiefOfLondon\screenshots\`.
- The Ultra preset at golden hour or in the fog shows the game best.

**Other page details:**
- **System requirements:** use the table in `installer/README.txt`.
- **Content survey:** fill it in (crime, non-lethal violence, alcohol).
- **Age rating:** get a free rating through IARC in Steamworks.

### 3. Launch options

**Installation → General:**

| Option | Executable | Arguments |
|---|---|---|
| Launch option 1 | `TheThiefOfLondon.exe` | none |
| Launch option 2 ("Safe mode") | `TheThiefOfLondon.exe` | `--rendering-driver d3d12` |

### 4. Steam Cloud (saves follow the player between PCs)

1. Go to **Application → Steam Cloud** and turn on **Auto-Cloud**.
2. Set the byte quota to 10 MB and the file count to 20.
3. Add these root paths:

| Root | Subdirectory | Pattern |
|---|---|---|
| `WinAppDataRoaming` | `ThiefOfLondon/saves` | `*.json` |
| `WinAppDataRoaming` | `ThiefOfLondon` | `settings.cfg` |

### 5. Upload a build

1. Download the **Steamworks SDK**. `steamcmd.exe` is in `sdk\tools\ContentBuilder\builder\`.
2. Fill in `tools\steam\steam_ids.txt`: `APP_ID`, `DEPOT_ID`, and your Steam account name as `STEAM_USER`.
3. Build the game (Part 3).
4. Run:

   ```bat
   tools\steam\upload.bat C:\steamworks_sdk\tools\ContentBuilder\builder\steamcmd.exe
   ```

   The first time, steamcmd asks for your password and Steam Guard code.
5. In Steamworks, go to **SteamPipe → Builds**. Set the new build live on a **beta** branch first and test it through Steam, then on **default**.

### 6. Steam Deck

The Windows build runs on the Deck through Proton, and so does controller play (every
action has a controller binding, and the settings menu rebinds pads). Request **Steam Deck
Verified** review in Steamworks. For Deck, the **Medium** preset holds 30+ fps.

### 7. Optional Steam features

**Achievements** (for example "Act One complete" or "The Legend of London") and **rich
presence** need the **GodotSteam** add-on (<https://godotsteam.com>). With it, you can call
Steam from `Story.bus().mission_completed` and `Progress.bus().legend_changed`.

## Part 6 — Releasing on itch.io

1. Create the project page at <https://itch.io/game/new>. Set the kind to "Downloadable", and set the pricing.
2. Install **butler** (<https://itch.io/docs/butler/>), then run `butler login` once.
3. Build with `tools/build_release.sh` (or `build_windows.bat` and zip `builds\windows`).
4. Upload:

   ```bash
   tools/publish_itch.sh yourname/the-thief-of-london
   ```

   This pushes the **windows** and **linux** channels with the version number. butler
   uploads only what changed, and players using the itch app get small patch updates.

5. You can also upload the Inno Setup installer as an extra file on the page.

## Part 7 — Code signing (no "Windows protected your PC" warning)

Unsigned downloads trigger Microsoft SmartScreen until they have built up reputation.

**Options:**
- **Azure Trusted Signing:** the cheapest, around US$10 a month, for individuals and companies.
- **An OV or EV code-signing certificate** from a certificate authority.

**Signing with `signtool`** (from the Windows SDK):

```bat
signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /a builds\windows\TheThiefOfLondon.exe
signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /a installer\Output\TheThiefOfLondon-0.11.0-Setup.exe
```

1. Sign the game first.
2. Build the installer.
3. Sign the installer.

Godot can also sign during export: tick **Code Signing** in the Windows preset and point it at your certificate.

Steam doesn't need signed builds, but signing still helps players who run the .exe directly.

## Part 8 — Release checklist

- [ ] `tools/set_version.sh` with the new version, and commit.
- [ ] All tests pass: `tests/run_tests.sh <godot>`.
- [ ] Build, then run the Part 4 checklist on a clean PC.
- [ ] Sign the exe and the installer (optional).
- [ ] Steam: upload, test on a beta branch, then set live. itch.io: publish.
- [ ] Tag the release in git: `git tag v0.11.0 && git push --tags`.

## Part 9 — What's been tested

**`tests/test_release.gd` (15 checks):**
- the presets exist
- tests and tools are left out of the game
- the icon is a real multi-size `.ico`, and the window icon is set
- the version is the same in the game, the `.exe` details and the installer
- the installer ships the Read Me, licence and third-party notices (including Godot's MIT licence)
- uninstalling asks before deleting saves, and uses the game's save folder
- the game's `--smoke-test` check is wired up

**The real export (Godot 4.7.2 templates):**

| Build | What was checked |
|---|---|
| **Windows** | `TheThiefOfLondon.exe` (with the icon, version 0.11.0.0, the product name and copyright in its file properties), `TheThiefOfLondon.console.exe` and `TheThiefOfLondon.pck` |
| **Linux** | Ran its self-check: `TheThiefOfLondon.x86_64 --headless -- --smoke-test` loads the title screen, then London and the hills, runs each for a few seconds, and prints `SMOKE OK` |

The same `--smoke-test` works on the Windows build, so run it on your PC after building:

```bat
builds\windows\TheThiefOfLondon.console.exe --headless -- --smoke-test
```

**Not run here:** the Inno Setup compiler runs only on Windows, so compile
`installer\thief_of_london.iss` once on your PC and try an install and an uninstall
(Part 4).
