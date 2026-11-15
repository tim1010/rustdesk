<#
.SYNOPSIS
Packs the MSP host-only build into an MSI ("HGC IT MSP Access") with the repo's WiX
project (res/msi), then restores res/msi.

.DESCRIPTION
Build the MSP client first (with RUSTDESK_MSP_HOST=1), and copy its Release folder to
-Source. The MSI:
  - shows -DisplayName in Add/Remove Programs, with the HGC IT logo as its icon
  - is marked incoming-only (installs and starts the service)
  - uses -AppName (the MSP build's internal app name, MSP_APP_NAME in src/common.rs) for
    the exe, install folder, service and registry keys, so it installs alongside a
    standard RustDesk rather than replacing it
  - names the Start menu folder and shortcut -DisplayName, and creates no desktop shortcut

The Quick Access build (RUSTDESK_QUICK_ACCESS=1) uses the same script with its own
names, -ConnType outgoing (no service) and -ExtraScheme rustdesk.

.EXAMPLE
.\build-msp-msi.ps1
.\build-msp-msi.ps1 -Source D:\out\Release -OutDir D:\out
.\build-msp-msi.ps1 -DisplayName 'HGC IT Quick Access' -AppName HGCITQuickAccess -ConnType outgoing -StageName quick-access -FileName hgcit-quick-access-1.5.3-x64.msi -ExtraScheme rustdesk
#>
param(
    # The MSP host build's Release folder. Defaults to <repo>\..\builds\msp-host\Release.
    [string]$Source,
    # Where the .msi is written. Defaults to <repo>\..\builds\msp-host.
    [string]$OutDir,
    # Name shown in Add/Remove Programs; matches MSP_TITLE in src/common.rs.
    [string]$DisplayName = 'HGC IT MSP Access',
    # Internal app name; must match MSP_APP_NAME in src/common.rs (no spaces).
    [string]$AppName = 'HGCITMSPAccess',
    # incoming: MSP host (installs the service). outgoing: Quick Access (no service).
    [ValidateSet('incoming', 'outgoing')]
    [string]$ConnType = 'incoming',
    # Build and staging folder name: <repo>\..\builds\<name>, <repo>\..\msi-stage\<name>.
    [string]$StageName = 'msp-host',
    # Output file name. Defaults to rustdesk-msp-host-<version>-x64.msi.
    [string]$FileName,
    # A URL scheme to register to the app as well as its own, e.g. 'rustdesk'.
    [string]$ExtraScheme = '',
    [string]$MSBuild = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
)
$ErrorActionPreference = 'Stop'
$Repo = $PSScriptRoot
$Root = Split-Path $Repo -Parent
if (-not $Source) { $Source = "$Root\builds\$StageName\Release" }
if (-not $OutDir) { $OutDir = "$Root\builds\$StageName" }
$Stage = "$Root\msi-stage\$StageName\rustdesk"

if (-not (Test-Path "$Source\$AppName.exe") -and -not (Test-Path "$Source\rustdesk.exe")) { throw "MSP build not found at $Source" }
if (-not (Test-Path $MSBuild)) { throw "MSBuild not found at $MSBuild" }

# Stage a clean copy of the app folder, with the exe named after the app.
if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
New-Item -ItemType Directory -Force $Stage | Out-Null
Copy-Item -Recurse "$Source\*" $Stage
if (Test-Path "$Stage\rustdesk.exe") {
    if (Test-Path "$Stage\$AppName.exe") { Remove-Item -Force "$Stage\rustdesk.exe" }
    else { Rename-Item "$Stage\rustdesk.exe" "$AppName.exe" }
}
New-Item -ItemType Directory -Force $OutDir | Out-Null

Push-Location "$Repo\res\msi"
try {
    python preprocess.py -d $Stage --conn-type $ConnType --app-name $AppName -m 'HGC IT Solutions Limited'
    if ($LASTEXITCODE -ne 0) { throw "preprocess.py failed" }

    # Start menu folder and shortcut names: the display name, not the internal app name.
    $folders = 'Package\Components\Folders.wxs'
    $t = Get-Content -Raw $folders
    if ($t -notmatch '<Directory Id="App.StartMenu" Name="\$\(var\.Product\)" />') { throw "App.StartMenu folder not found in $folders" }
    $t = $t.Replace('<Directory Id="App.StartMenu" Name="$(var.Product)" />', "<Directory Id=""App.StartMenu"" Name=""$DisplayName"" />")
    [IO.File]::WriteAllText((Resolve-Path $folders), $t, [Text.UTF8Encoding]::new($true))
    foreach ($wxl in Get-ChildItem 'Package\Language\Package.*.wxl') {
        $t = Get-Content -Raw $wxl.FullName
        $t = $t -replace '<String Id="SC_Client" Value="[^"]*"', "<String Id=""SC_Client"" Value=""$DisplayName"""
        $t = $t -replace '<String Id="SC_Client_Desc" Value="[^"]*"', "<String Id=""SC_Client_Desc"" Value=""Start $DisplayName."""
        $t = $t -replace '<String Id="SC_Uninstall" Value="[^"]*"', "<String Id=""SC_Uninstall"" Value=""Uninstall $DisplayName"""
        [IO.File]::WriteAllText($wxl.FullName, $t, [Text.UTF8Encoding]::new($true))
    }

    # No desktop shortcut: drop the component and the installer's checkbox for it.
    $comp = 'Package\Components\RustDesk.wxs'
    $t = Get-Content -Raw $comp
    $desktop = [regex]'(?s)\s*<StandardDirectory Id="DesktopFolder">\s*<Component Id="App\.Desktop\.Shortcut".*?</StandardDirectory>'
    if (-not $desktop.IsMatch($t)) { throw "Desktop shortcut component not found in $comp" }
    $t = $desktop.Replace($t, '', 1)
    $t = $t -replace '\s*<ComponentRef Id="App\.Desktop\.Shortcut" />', ''
    [IO.File]::WriteAllText((Resolve-Path $comp), $t, [Text.UTF8Encoding]::new($true))
    $dlg = 'Package\UI\MyInstallDirDlg.wxs'
    $t = Get-Content -Raw $dlg
    $t = $t -replace '\s*<Control Id="ChkBoxDesktopShortcuts"[^>]*/>', ''
    [IO.File]::WriteAllText((Resolve-Path $dlg), $t, [Text.UTF8Encoding]::new($true))

    # Extra URL scheme (Quick Access answers rustdesk:// too). Known limit: the MSI removes
    # this key on uninstall even if another app has taken the scheme over since.
    if ($ExtraScheme) {
        $regs = 'Package\Components\Regs.wxs'
        $t = Get-Content -Raw $regs
        $anchor = '<Component Id="Product.Registry.InstallState"'
        if (-not $t.Contains($anchor)) { throw "InstallState component not found in $regs" }
        $component = "<Component Id=""Product.Registry.ExtraScheme"" Guid=""4F7C2A61-9B3E-4D85-A1C6-3E2B7D9F0A14"">`r`n" +
            "`t`t`t`t<RegistryKey Root=""HKCR"" Key=""$ExtraScheme"">`r`n" +
            "`t`t`t`t`t<RegistryValue Type=""string"" Name=""URL Protocol"" Value="""" />`r`n" +
            "`t`t`t`t</RegistryKey>`r`n" +
            "`t`t`t`t<RegistryKey Root=""HKCR"" Key=""$ExtraScheme\shell\open\command"">`r`n" +
            "`t`t`t`t`t<RegistryValue Type=""string"" Value='""[INSTALLFOLDER_INNER]`$(var.Product).exe"" ""%1""' />`r`n" +
            "`t`t`t`t</RegistryKey>`r`n" +
            "`t`t`t</Component>`r`n`r`n`t`t`t"
        $t = $t.Replace($anchor, $component + $anchor)
        [IO.File]::WriteAllText((Resolve-Path $regs), $t, [Text.UTF8Encoding]::new($true))
        $pkg = 'Package\Package.wxs'
        $t = Get-Content -Raw $pkg
        $ref = '<ComponentRef Id="Product.Registry.Command" />'
        if (-not $t.Contains($ref)) { throw "Product.Registry.Command ref not found in $pkg" }
        $t = $t.Replace($ref, "$ref`r`n`t`t`t<ComponentRef Id=""Product.Registry.ExtraScheme"" />")
        [IO.File]::WriteAllText((Resolve-Path $pkg), $t, [Text.UTF8Encoding]::new($true))
    }

    # Add/Remove Programs icon: HGC IT logo instead of the RustDesk one.
    Copy-Item -Force "$Repo\flutter\assets\msp_logo.ico" "Package\Resources\icon.ico"

    # Add/Remove Programs name. Only the MSI ProductName changes; $(var.Product) stays
    # "RustDesk" so the install folder, service, registry keys and exe name match the app.
    $pkg = 'Package\Package.wxs'
    $t = Get-Content -Raw $pkg
    if ($t -notmatch '<Package Name="\$\(var\.Product\)"') { throw "Package Name attribute not found in $pkg" }
    $t = $t.Replace('<Package Name="$(var.Product)"', "<Package Name=""$DisplayName""")
    [IO.File]::WriteAllText((Resolve-Path $pkg), $t, [Text.UTF8Encoding]::new($true))
    # The printer actions use [ProductName] as the printer name; keep them on the app name.
    $comp = 'Package\Components\RustDesk.wxs'
    $t = Get-Content -Raw $comp
    $t = $t.Replace('Property="InstallPrinter" Value="[ProductName]|', 'Property="InstallPrinter" Value="$(var.Product)|')
    $t = $t.Replace('Property="UninstallPrinter" Value="[ProductName]"', 'Property="UninstallPrinter" Value="$(var.Product)"')
    [IO.File]::WriteAllText((Resolve-Path $comp), $t, [Text.UTF8Encoding]::new($true))

    & $MSBuild msi.sln -t:Restore -p:Configuration=Release -p:Platform=x64
    if ($LASTEXITCODE -ne 0) { throw "msbuild restore failed" }
    & $MSBuild msi.sln -t:Clean -p:Configuration=Release -p:Platform=x64
    & $MSBuild msi.sln -p:Configuration=Release -p:Platform=x64 /p:TargetVersion=Windows10
    if ($LASTEXITCODE -ne 0) { throw "msbuild failed" }

    $msi = Get-ChildItem .\Package\bin\*\Release\en-us\Package.msi | Select-Object -First 1
    $ver = (Select-String -Path "$Repo\Cargo.toml" -Pattern '^version = "(.+)"').Matches[0].Groups[1].Value
    if (-not $FileName) { $FileName = "rustdesk-msp-host-$ver-x64.msi" }
    $dest = "$OutDir\$FileName"
    Move-Item -Force $msi.FullName $dest
    Write-Host "MSI: $dest" -ForegroundColor Green
}
finally {
    # preprocess.py rewrites tracked files under res/msi; put them back.
    git -C $Repo checkout -- res/msi
    Pop-Location
}
