# HGC IT Quick Access: branded controller build — design

Date: 2026-11-15. Fork: tim1010/rustdesk, branch `custom-client` (push to the fork only, never upstream).

## Intent

HGC IT already ships a branded, host-only build, "HGC IT MSP Access" (`RUSTDESK_MSP_HOST=1`).
The other build — the "standard" one technicians use to connect *out* to customers — is still
plain RustDesk. It should become a branded controller, **"HGC IT Quick Access"**, that shows
only what a technician needs: the box to type a remote ID and connect.

Why: a consistent HGC IT product pair (Quick Access to connect, MSP Access on customer PCs),
and a cleaner controller with nothing about "your desktop" on it.

## Goals

1. Quick Access home page has **no left "Your Desktop" panel** (ID, one-time password, tips,
   help cards) and **no "Control Remote Desktop" heading**.
2. Same branding as MSP Access: HGC IT logo on the home page, centred title
   "HGC IT Quick Access", window title, taskbar/Alt-Tab icon, exe icon and version
   strings, portable-installer icon, Start menu folder/shortcut name, Add/Remove Programs name
   and icon, no desktop shortcut.
3. Internal app name **`HGCITQuickAccess`** (exe `HGCITQuickAccess.exe`, install folder,
   config folder `%APPDATA%\HGCITQuickAccess`, registry keys). It installs alongside RustDesk
   and alongside MSP Access.
4. Opens **both** `hgcitquickaccess://…` and `rustdesk://…` links, e.g.
   `rustdesk://15906157@rd.hgcit.co.uk?key=…` connects.
5. Works on a fresh PC against `rd.hgcit.co.uk` with its key, with no hand-edited config.
6. Built by `setup-rustdesk-build.ps1` in place of the plain standard build; `-Variant Both`
   produces Quick Access + MSP Access, each with portable exe and MSI, optionally signed.

## Non-goals

- No change to MSP Access behaviour or output.
- No plain unbranded RustDesk build any more (user chose replacement). It can still be built
  by running build.py without either switch, but the build script no longer offers it.
- No IP whitelist, fixed password, or account features.
- No macOS/Linux/mobile work.

## Anti-goals (failure even if it "works")

- MSP Access picks up any Quick Access change (e.g. loses its left panel, gains rustdesk://).
- Settings become unreachable once the left panel goes.
- Uninstalling Quick Access breaks a separately installed RustDesk's `rustdesk://` handler
  (install-script path must not do this; see MSI limitation below).

## Approaches

- **A. New compile-time switch `RUSTDESK_QUICK_ACCESS=1`, parallel to `RUSTDESK_MSP_HOST` —
  chosen by the user.** Shared branding code is switched on for either build; only names
  differ. Layout and link changes are gated on the Quick Access switch. Builds stay isolated.
- B. Change the standard build directly, no switch. Fewer lines, but the home page and
  branding code are shared with MSP Access so every change still needs "not MSP" guards, and
  there is no way back to an unbranded build. Rejected.

## Decisions (user)

- Name: internal `HGCITQuickAccess`, display "HGC IT Quick Access".
- Replaces the standard variant in the build script.
- Answer both `rustdesk://` and `hgcitquickaccess://`.
- Approach A.

- Outgoing-only (call 1) and server as editable defaults (call 2): user accepted the
  recommendations ("carry on", 2026-11-15).

## Decisions (my calls)

1. **Outgoing-only.** (Accepted by the user.) Quick Access sets hard setting `conn-type=outgoing` (MSP Access uses
   `incoming`). Removing the "Your Desktop" panel means nobody can read this PC's ID/password
   anyway, so it should not accept incoming sessions or install a service for them. The MSI
   is built with `--conn-type outgoing`.
2. **Server built in as defaults, not locked.** (Accepted by the user.) `custom-rendezvous-server`, relay and API
   `rd.hgcit.co.uk`, key `RpchEQc2AGDpCBqefAhjnwb3kH0ln8wRGKwbUC2Jh6Y=` go into
   `DEFAULT_SETTINGS` (MSP Access uses `OVERWRITE_SETTINGS`). Fresh installs work; the
   settings page stays usable for a technician who needs another server.
3. **Settings gear** moves to the connect page (bottom-left, same look as RustDesk's
   outgoing-only gear), since its usual home is the removed panel.
4. **Heading replacement.** Where "Control Remote Desktop" was, show the HGC IT logo and the
   centred "HGC IT Quick Access" title (as MSP Access shows at the top of its panel). The ID
   help "?" icon goes with the heading.
5. **Install/upgrade bar kept.** The "Install" and "Click to upgrade" cards from
   `buildHelpCards` (`desktop_home_page.dart` ~468–482) are the only in-app way for the portable
   exe to install itself, so they move to a small bar on the connect page, shown only when not
   installed / installed lower version. Other help cards (the "new RustDesk version" card that
   links to upstream GitHub, permission prompts) are dropped with the panel.
5a. **No tray.** Outgoing-only means no service and no tray process, so there is no tray icon
   or start-at-login. `tray.rs` still uses `is_branded()` for the asset (free, harmless).
5b. **custom.txt.** Not used by the current standard build; the built-in defaults replace it.
   `load_custom_client_file()` is left as is, so a dropped-in file is still honoured. The
   stale "copy custom.txt" notes in `setup-rustdesk-build.ps1` are removed.
6. **`rustdesk://` registration on uninstall (install-script path):** remove `HKCR\rustdesk`
   only if its open command points at the Quick Access exe.
   **MSI limitation:** a WiX registry component removes the key it wrote on uninstall
   regardless; if RustDesk is also installed, reinstall/repair RustDesk to restore its handler.
   Documented, not engineered around.
7. **Output names:** `builds\quick-access\Release\HGCITQuickAccess.exe`,
   `builds\quick-access\hgcit-quick-access-1.5.3-install.exe`,
   `builds\quick-access\hgcit-quick-access-1.5.3-x64.msi`. `-Variant` becomes
   `Both|QuickAccess|Msp`.
8. `build-msp-msi.ps1` is generalised (parameters for display name, app name, conn type,
   source/output/file name, extra URL scheme) rather than copied, and called for both builds.

## How it works today (relevant parts)

- `src/common.rs` ~2509–2582: `load_custom_client()` → `apply_msp_host_lock()`; `is_msp_host_lock()`
  reads `option_env!("RUSTDESK_MSP_HOST")`; sets `APP_NAME`, hard/overwrite/builtin settings,
  builtin `msp-title` = "HGC IT MSP Access" and `msp-hide-id-password`. `get_shortcut_name()`.
  Also called from `src/flutter_ffi.rs:55`.
- Flutter: `getMspTitle()` (`common.dart:3064`) drives logo (`msp_logo.png`), window icon
  (`msp_logo.ico`), `loadIcon`, and the window title; `desktop_home_page.dart` builds left pane
  (78–182) and right pane; `connection_page_title.dart` renders "Control Remote Desktop".
- Windows: `Runner.rc` icon + version strings under `#ifdef RUSTDESK_MSP_HOST`; runner
  `CMakeLists.txt:32` defines it from the env; `libs/portable/build.rs` picks the packer icon
  from the env; `src/tray.rs:309` picks the tray asset; `src/platform/windows.rs` strips
  `desktopicon` (~1660) and pins the server in `get_license_from_exe_name` (~2184).
- Links: `get_uri_prefix()` = `<app name lowercase>://` (`common.rs:1236`), checked in
  `core_main.rs:187`, `is_empty_uni_link` (`common.rs:2756`), `handleUriLink`
  (`common.dart:2261`), `model.dart:747`; registered in the install script
  (`windows.rs` ~1615) and MSI `Regs.wxs` (`Product.Registry.URLProtocol`/`Command`).

## Design

**Rust (`src/common.rs`)**
- `is_quick_access()` = `option_env!("RUSTDESK_QUICK_ACCESS") == Some("1")`;
  constants `QA_APP_NAME = "HGCITQuickAccess"`, `QA_TITLE = "HGC IT Quick Access"`.
- `apply_quick_access()` called next to `apply_msp_host_lock()` (both call sites): sets
  `APP_NAME`, hard `conn-type=outgoing`, `DEFAULT_SETTINGS` for server/relay/API/key,
  builtin `msp-title` = QA_TITLE, builtin `quick-access` = `Y` (Flutter layout flag).
  Builtin hide flags for server/network settings are NOT set.
- `is_branded()` = MSP || QA; `get_shortcut_name()` returns the right title for either.
- Link prefixes: `get_uri_prefixes()` returns `[get_uri_prefix()]` plus `rustdesk://` when QA;
  `core_main.rs:187` and `is_empty_uni_link` accept any of them. Expose to Flutter (new FFI
  sync fn, or make `handleUriLink` also accept `rustdesk://` when the `quick-access` builtin
  is set). `urlLinkToCmdArgs` already parses either scheme identically.
- `tray.rs`, `windows.rs` desktopicon strip: use `is_branded()`.
- Install script (`windows.rs` ~1615): when QA, also write the `HKCR\rustdesk` protocol keys
  pointing at the QA exe; uninstall removes them only if they point at the QA exe.

**Flutter**
- `desktop_home_page.dart`: when `quick-access` builtin is `Y`, `build` shows only the right
  pane (no left pane, no divider), with the settings gear overlaid bottom-left.
- `connection_page_title.dart`: when QA, render logo + centred `getMspTitle()` instead of the
  "Control Remote Desktop" row.
- Window-size logic for incoming-only is unaffected (QA is outgoing-only).

**Windows runner / packer**
- `CMakeLists.txt`: define `RUSTDESK_QUICK_ACCESS` from the env.
- `Runner.rc`: `#if defined(RUSTDESK_MSP_HOST) || defined(RUSTDESK_QUICK_ACCESS)` for the
  icon; a QA version-string block (FileDescription/ProductName "HGC IT Quick Access",
  InternalName "HGCITQuickAccess", OriginalFilename "HGCITQuickAccess.exe",
  CompanyName "HGC IT Solutions Limited").
- `libs/portable/build.rs`: HGC icon if either env var is `1`; rerun on both.

**MSI / build scripts**
- Generalised MSI script (see call 8): QA run uses `--conn-type outgoing`,
  `--app-name HGCITQuickAccess`, display name "HGC IT Quick Access", plus an extra component
  registering `HKCR\rustdesk` → QA exe. Always `git checkout -- res/msi` afterwards.
- `setup-rustdesk-build.ps1`: `Build-Variant` takes a variant id; QA sets
  `RUSTDESK_QUICK_ACCESS=1` (and clears the MSP var, and vice versa), renames
  `rustdesk.exe` → `HGCITQuickAccess.exe`, packs, copies to `builds\quick-access`, builds MSI,
  signs with `-Sign`. Update help text and the stale "Next:" notes.

## Verification

- Build `-Variant Both` (with and without `-Sign` as before); both succeed.
- Quick Access: launches with no left panel, no "Control Remote Desktop", logo + title shown,
  window/taskbar icons HGC, install bar shown when run portable, settings reachable from the gear, server fields pre-filled.
- Connect to a known host via the ID box, via `hgcitquickaccess://15906157@rd.hgcit.co.uk?key=…`
  and via `rustdesk://…` (both with the app closed and already running).
- MSI install, and install via the portable exe's install bar: Start menu "HGC IT Quick Access", no desktop shortcut, ARP name
  and icon, both protocol keys point at `HGCITQuickAccess.exe`; no service installed.
- MSP Access rebuilt from the same tree: unchanged behaviour (left panel, incoming-only, no
  `rustdesk://`).
- `git status` clean apart from intended changes; `res/msi` and `res/manifest.xml` restored.

## Left to the builder

Exact widget structure/placement of the gear and heading; FFI shape for the extra prefix;
how the MSI script is parameterised; commit granularity.
