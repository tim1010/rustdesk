# HGC IT Quick Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the plain "standard" build into the branded, connect-out-only controller "HGC IT Quick Access" (`RUSTDESK_QUICK_ACCESS=1`), with no "Your Desktop" panel, no "Control Remote Desktop" heading, and support for both `hgcitquickaccess://` and `rustdesk://` links.

**Architecture:** A compile-time switch parallel to `RUSTDESK_MSP_HOST`. Rust sets the app name, outgoing-only, default server and builtin flags at startup. Flutter reads builtin options (`msp-title`, new `quick-access`), so no new FFI is needed. The Windows runner, the portable packer, the MSI script and the build script each pick up the env var.

**Tech Stack:** Rust (hbb_common config), Flutter desktop (Dart), Win32 resource script/CMake, WiX via `res/msi/preprocess.py`, PowerShell.

**Spec:** `docs/superpowers/specs/2026-11-15-quick-access-client-design.md`

## Global Constraints

- Internal app name `HGCITQuickAccess` (no spaces); display name `HGC IT Quick Access`; company `HGC IT Solutions Limited`.
- Server defaults (editable, `DEFAULT_SETTINGS`, NOT overwrite): `custom-rendezvous-server`=`rd.hgcit.co.uk`, `relay-server`=`rd.hgcit.co.uk`, `api-server`=`https://rd.hgcit.co.uk`, `key`=`RpchEQc2AGDpCBqefAhjnwb3kH0ln8wRGKwbUC2Jh6Y=` (reuse the `MSP_*` constants).
- Hard setting `conn-type`=`outgoing`.
- MSP Access (`RUSTDESK_MSP_HOST=1`) behaviour and output must not change.
- Never set both env vars; the build script clears the other one.
- Pinned toolchain versions in `setup-rustdesk-build.ps1` must not change.
- Commit to branch `custom-client`; push only to `origin` (tim1010/rustdesk) and only when the user asks. Never upstream.
- Builds must run inside the vcvars wrapper (VS 2022 `vcvars64.bat`, then `set VCPKG_ROOT=E:\Coding\rust\vcpkg`, with `E:\Coding\rust\flutter\bin` first on PATH).

## Review Focus

1. A `rustdesk://` link arriving while Quick Access is **already running** (goes through `onUrlSchemeReceived` in `model.dart`, not `handleUriLink`'s cmdArgs path). It must connect, not be ignored. Covered in Task 6, step 4.
2. An empty link (`rustdesk://` or `hgcitquickaccess://` with nothing after it) should just open the main window, not error. Covered by the `quick_access_uri_prefixes` unit test (Task 1) and Task 6.
3. Uninstalling Quick Access when `HKCR\rustdesk` belongs to a separately installed RustDesk: the key must stay. Covered by the Task 2 test on the uninstall command.
4. Settings must be reachable with the left panel gone (gear on the connect page). Covered in Task 6, step 3.
5. A non-HGC `custom.txt` dropped next to the exe still loads (it runs before `apply_quick_access`); the built-in defaults must not erase its overrides. `DEFAULT_SETTINGS` only fills gaps, which is accepted behaviour. Note it in Task 6; no test needed.

---

### Task 1: Rust core switch, settings and link prefixes

**Files:**
- Modify: `src/common.rs` (~1236 `get_uri_prefix`, ~2509–2582 MSP block, ~2756 `is_empty_uni_link`, tests module ~3173)
- Modify: `src/flutter_ffi.rs:55` (call `apply_quick_access()` next to `apply_msp_host_lock()`)
- Modify: `src/tray.rs:309`, `src/platform/windows.rs:~1660` (use `is_branded()`)

**Interfaces:**
- Produces:
  - `pub fn is_quick_access() -> bool` (`option_env!("RUSTDESK_QUICK_ACCESS") == Some("1")`)
  - `pub const QA_APP_NAME: &str = "HGCITQuickAccess"`, `pub const QA_TITLE: &str = "HGC IT Quick Access"`
  - `pub const OPTION_QUICK_ACCESS: &str = "quick-access"` (builtin, value `"Y"`)
  - `pub fn is_branded() -> bool` (MSP or QA)
  - `pub fn apply_quick_access()`, called from `load_custom_client()` and `flutter_ffi.rs:55`
  - `fn quick_access_uri_prefixes(app_name: &str, quick_access: bool) -> Vec<String>` (pure; returns `["<app lower>://"]`, plus `"rustdesk://"` when `quick_access` and it differs)
  - `pub fn get_uri_prefixes() -> Vec<String>` = `quick_access_uri_prefixes(&get_app_name(), is_quick_access())`
  - `get_shortcut_name()` returns `QA_TITLE` when QA

- [ ] **Step 1: Write the failing tests** in `src/common.rs` `mod tests`:

```rust
#[test]
fn quick_access_uri_prefixes_adds_rustdesk_only_for_quick_access() {
    assert_eq!(quick_access_uri_prefixes("HGCITQuickAccess", true),
               vec!["hgcitquickaccess://".to_owned(), "rustdesk://".to_owned()]);
    assert_eq!(quick_access_uri_prefixes("HGCITMSPAccess", false),
               vec!["hgcitmspaccess://".to_owned()]);
    assert_eq!(quick_access_uri_prefixes("RustDesk", true), vec!["rustdesk://".to_owned()]);
}

#[test]
fn empty_uni_link_matches_any_prefix() {
    let p = quick_access_uri_prefixes("HGCITQuickAccess", true);
    assert!(is_empty_uni_link_for("rustdesk://", &p));
    assert!(is_empty_uni_link_for("hgcitquickaccess:///", &p));
    assert!(!is_empty_uni_link_for("rustdesk://15906157", &p));
    assert!(!is_empty_uni_link_for("other://", &p));
}
```

(`is_empty_uni_link_for(arg: &str, prefixes: &[String]) -> bool` is the pure core; `is_empty_uni_link(arg)` calls it with `get_uri_prefixes()`.)

- [ ] **Step 2: Run the tests and check they fail**

Run (from a cmd shell): `call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" && set VCPKG_ROOT=E:\Coding\rust\vcpkg && cd /d E:\Coding\rust\rustdesk && cargo test --lib --features flutter quick_access_uri_prefixes empty_uni_link`
Expected: compile error, `quick_access_uri_prefixes` not found.

- [ ] **Step 3: Implement** the Interfaces items above. `apply_quick_access()` returns early unless `is_quick_access()`, then:
  - sets `APP_NAME` to `QA_APP_NAME`;
  - sets `HARD_SETTINGS` `conn-type`=`outgoing`;
  - fills `DEFAULT_SETTINGS` with the four server values;
  - sets `BUILTIN_SETTINGS` `msp-title`=`QA_TITLE` and `quick-access`=`Y`;
  - sets `EXE_RENDEZVOUS_SERVER` too. It does NOT set the hide-server/network builtins or `msp-hide-id-password`.

  `tray.rs` and the `desktopicon` strip in `windows.rs` switch from `is_msp_host_lock()` to `is_branded()`. `get_license_from_exe_name` stays MSP-only.

- [ ] **Step 4: Run the tests and check they pass.** Same command. Expected: 2 passed.

- [ ] **Step 5: Commit** — `git commit -m "Add Quick Access build switch, defaults and link prefixes"`

### Task 2: Register `rustdesk://` in the install script

**Files:**
- Modify: `src/platform/windows.rs` (~1615 install cmds, ~1860 `get_before_uninstall`)

**Interfaces:**
- Consumes: `is_quick_access()` (Task 1)
- Produces: `fn extra_scheme_install_cmds(exe: &str) -> String`, `fn extra_scheme_uninstall_cmds(exe: &str) -> String` (pure, unconditional). Callers include them only when `is_quick_access()`.

- [ ] **Step 1: Write the failing tests** (in `windows.rs` tests, or a `#[cfg(test)]` module beside them):

```rust
#[test]
fn extra_scheme_cmds_target_rustdesk_key_and_our_exe() {
    let exe = r"C:\Program Files\HGCITQuickAccess\HGCITQuickAccess.exe";
    let i = extra_scheme_install_cmds(exe);
    assert!(i.contains(r#"reg add HKEY_CLASSES_ROOT\rustdesk /f /v "URL Protocol""#));
    assert!(i.contains(r"HKEY_CLASSES_ROOT\rustdesk\shell\open\command"));
    assert!(i.contains(exe));
    let u = extra_scheme_uninstall_cmds(exe);
    // Only deletes when the open command still points at our exe.
    assert!(u.contains("findstr /I /C:\"HGCITQuickAccess.exe\""));
    assert!(u.contains(r"&& reg delete HKEY_CLASSES_ROOT\rustdesk /f"));
}
```

- [ ] **Step 2: Run and check it fails.** Run: as in Task 1, with the filter `extra_scheme_cmds`. Expected: not found.
- [ ] **Step 3: Implement.** Install mirrors the existing `{ext}` URL-protocol lines with `rustdesk`, using the `"{nested_exe}" "%%1"` command format already used there. Uninstall: `reg query HKEY_CLASSES_ROOT\rustdesk\shell\open\command /ve | findstr /I /C:"<exe file name>" && reg delete HKEY_CLASSES_ROOT\rustdesk /f`. Splice both into the existing format strings under `if is_quick_access()`.
- [ ] **Step 4: Run and check it passes.**
- [ ] **Step 5: Commit** — `"Register rustdesk:// for Quick Access installs"`

### Task 3: Flutter — layout, heading, gear, install bar, link prefixes

**Files:**
- Modify: `flutter/lib/common.dart` (add `bool isQuickAccess()`, `bool isOurUriLink(String s)`; use at ~2261)
- Modify: `flutter/lib/models/model.dart:747` (use `isOurUriLink(url)`)
- Modify: `flutter/lib/desktop/pages/desktop_home_page.dart` (`build` ~58, extract the install/upgrade card logic ~468–482 into a reusable `Widget? buildInstallBar()`)
- Modify: `flutter/lib/common/widgets/connection_page_title.dart`

**Interfaces:**
- Produces: `bool isQuickAccess() => bind.mainGetBuildinOption(key: 'quick-access') == 'Y';` and `bool isOurUriLink(String s) => s.startsWith(bind.mainUriPrefixSync()) || (isQuickAccess() && s.startsWith('rustdesk://'));`

- [ ] **Step 1: Implement.**
  - `build`: when `isQuickAccess()`, render a Stack with `buildRightPane` filling the space, the install bar (if non-null) at the top, and the settings gear bottom-left. Reuse the existing outgoing-only gear widget, extracted into `Widget _buildSettingsGear(Color? textColor)`.
  - Leave the left-pane path unchanged for other builds.
  - `getConnectionPageTitle`: when `isQuickAccess()`, return a centred Column of `loadLogo()` and `Text(getMspTitle(), style: titleLarge)` instead of the "Control Remote Desktop" row.
  - Do not touch the incoming-only / MSP code paths.
- [ ] **Step 2: Static check.** Run: `cd flutter && E:\Coding\rust\flutter\bin\flutter analyze lib/common.dart lib/models/model.dart lib/desktop/pages/desktop_home_page.dart lib/common/widgets/connection_page_title.dart`. Expected: no new errors compared with `git stash`'d baseline. Warnings that existed before are fine.
- [ ] **Step 3: Commit** — `"Quick Access home page: connect box only, branded heading, gear and install bar"`

(Visual checks happen in Task 6, because the layout can only be seen in a real build.)

### Task 4: Windows runner and portable packer branding

**Files:**
- Modify: `flutter/windows/runner/CMakeLists.txt:32` (also define `RUSTDESK_QUICK_ACCESS` from the env)
- Modify: `flutter/windows/runner/Runner.rc:55,96` (icon under `#if defined(RUSTDESK_MSP_HOST) || defined(RUSTDESK_QUICK_ACCESS)`; new `#elif defined(RUSTDESK_QUICK_ACCESS)` version block: CompanyName `HGC IT Solutions Limited`, FileDescription/ProductName `HGC IT Quick Access`, InternalName `HGCITQuickAccess`, OriginalFilename `HGCITQuickAccess.exe`)
- Modify: `libs/portable/build.rs` (HGC icon when either env var is `1`; `rerun-if-env-changed` for both)

- [ ] **Step 1: Implement** the three edits.
- [ ] **Step 2: Verify** in Task 6 (the exe and packer icons, plus version strings via `(Get-Item exe).VersionInfo`).
- [ ] **Step 3: Commit** — `"Quick Access exe and portable installer branding"`

### Task 5: MSI and build script

**Files:**
- Modify: `build-msp-msi.ps1` → generalise. Add params `-ConnType` (default `incoming`), `-FileName` (default `rustdesk-msp-host-<ver>-x64.msi`), `-StageName` (default `msp-host`), `-ExtraScheme` (default empty). Keep the MSP defaults so the existing call stays the same. With `-ExtraScheme rustdesk`, inject into `Package\Components\Regs.wxs` a component (new fixed GUID) that writes `HKCR\rustdesk` (`URL Protocol` = "") and `HKCR\rustdesk\shell\open\command` = `"[INSTALLFOLDER_INNER]$(var.Product).exe" "%1"`, plus its `ComponentRef` wherever `Product.Registry.URLProtocol` is referenced.
- Modify: `E:\Coding\rust\setup-rustdesk-build.ps1`:
  - `-Variant Both|QuickAccess|Msp` (Both = QA + MSP).
  - `Build-Variant` takes `qa`/`msp` and sets one env var while clearing the other.
  - The QA build renames `rustdesk.exe` → `HGCITQuickAccess.exe` and outputs to `builds\quick-access`, with portable exe `hgcit-quick-access-<ver>-install.exe` and MSI via `build-msp-msi.ps1 -DisplayName 'HGC IT Quick Access' -AppName HGCITQuickAccess -ConnType outgoing -StageName quick-access -FileName hgcit-quick-access-<ver>-x64.msi -ExtraScheme rustdesk`.
  - Signing as for MSP.
  - Update the help text, and replace the stale "Next:" notes (custom.txt) with the output paths.

- [ ] **Step 1: Implement** both.
- [ ] **Step 2: Parse check.** Run: `pwsh -NoProfile -Command "[void][scriptblock]::Create((Get-Content -Raw E:\Coding\rust\setup-rustdesk-build.ps1)); [void][scriptblock]::Create((Get-Content -Raw E:\Coding\rust\rustdesk\build-msp-msi.ps1)); 'ok'"`. Expected: `ok`.
- [ ] **Step 3: Commit** the repo's `build-msp-msi.ps1` (the setup script lives outside the repo). Message: `"Generalise MSI script for the Quick Access build"`

### Task 6: Full build and verification

- [ ] **Step 1: Build.** Write scratchpad `build-qa-both.cmd`, a copy of the earlier wrapper (vcvars64, `VCPKG_ROOT`, `E:\Coding\rust\flutter\bin` first on PATH, clear both env vars) that runs `setup-rustdesk-build.ps1 -Dev E:\Coding\rust -BuildOnly -Variant Both` in the background. Log to `E:\Coding\rust\build-log-qa.txt`.
  Expected: EXIT 0, and these files exist:
  - `builds\quick-access\Release\HGCITQuickAccess.exe`
  - `builds\quick-access\hgcit-quick-access-1.5.3-install.exe`
  - `builds\quick-access\hgcit-quick-access-1.5.3-x64.msi`
  - the three `builds\msp-host` outputs
- [ ] **Step 2: Check the exe metadata.** `VersionInfo` shows ProductName `HGC IT Quick Access` for QA and `HGC IT MSP Access` for MSP. Extracted exe icons are the HGC logo for both.
- [ ] **Step 3: Launch Quick Access (portable) and take screenshots.**
  - There's no left panel, no "Control Remote Desktop", and the logo plus "HGC IT Quick Access" are at the top.
  - The window title is "HGC IT Quick Access" and the taskbar icon is HGC.
  - The install bar is shown.
  - The gear opens settings, and the network settings show `rd.hgcit.co.uk` and the key.
  - Typing 15906157 and connecting reaches the password prompt.
- [ ] **Step 4: Test the links.** With Quick Access running, run the QA exe with the arguments `rustdesk://15906157@rd.hgcit.co.uk?key=…` and then `hgcitquickaccess://…`. Each one opens a session to 15906157. Also run a cold start with a link argument.
- [ ] **Step 5: Check MSP Access.** Launch the MSP build: left panel and incoming-only exactly as before.
- [ ] **Step 6: Ask the user before installing.** Installing the MSI changes this PC and takes over `rustdesk://`. If they agree, install it and check:
  - Start menu entry "HGC IT Quick Access", no desktop shortcut;
  - Add/Remove Programs name and icon;
  - both `HKCR` keys point at `HGCITQuickAccess.exe`;
  - no service is installed.
- [ ] **Step 7: Clean the tree.** `git status` shows only intended changes; `res/msi` and `res/manifest.xml` are restored. Update memory `rustdesk-build-plan.md`. Ask the user whether to push.
