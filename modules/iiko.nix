# iiko RMS BackOffice, run under Wine. Declares the Wine build, the
# prefix location, and two wrapper commands -- the rest (actually
# downloading iiko's installer and running the one-time setup) is a
# manual step, since the installer is a large proprietary binary the
# user downloads themselves, not something that belongs in this flake
# or the Nix store.
#
# Getting this working at all took real investigation (session history
# has the full trail); the two load-bearing, non-obvious facts baked
# into iikoBackofficeInstall below are:
#
#   1. WINEARCH=win32 is mandatory, which rules out pkgs.wineWow64Packages
#      entirely (NixOS's default "unified" Wine build explicitly refuses
#      WINEARCH=win32: "this is not supported in wow64 mode"). Plain
#      pkgs.wine (the traditional, non-WOW64 build) supports it and is
#      still cache.nixos.org-cached, no source compile needed. This
#      isn't just an arbitrary choice -- `winetricks dotnet472` hangs
#      indefinitely under both wow64-new and wow64-old (i.e. under
#      wineWow64Packages entirely, regardless of WINEARCH) but installs
#      cleanly under a genuine win32 prefix (confirmed against multiple
#      2026-dated tester reports on Winetricks/winetricks#2138), and
#      iiko's installer needs .NET Framework 4.7.2 to get anywhere.
#
#   2. The bundled "Microsoft POS for .NET" prerequisite
#      (PosForDotNet_1.14.1.msi) will reliably fail during install --
#      not a Wine/prefix misconfiguration, but a genuine, deep gap in
#      Wine's WMI support: InstallUtil.exe runs for real and gets as far
#      as registering the Microsoft.PointOfService.WMI.dll provider, then
#      dies with `System.Management.ManagementException: Error code:
#      0x80041017` -- Wine ships WMI's stub DLLs but doesn't implement
#      actual class/schema registration. This package isn't needed for
#      BackOffice itself, so the installer's bootstrapper (Setup.RMS.
#      BackOffice.exe, a WiX Burn bundle) is deliberately allowed to
#      "fail" here and its actual application MSI is installed directly
#      afterwards instead of relying on the bundle to finish end-to-end.
#
#      That failure triggers Burn's rollback logic, which can race the
#      *unrelated*, already-successful async caching of BackOffice's own
#      payload cabinet (RMS.Office.cab) -- rollback cleanup of the shared
#      temp extraction directory can delete that cabinet's source file out
#      from under the in-flight move into Package Cache, leaving a bare
#      .msi with no sibling .cab (`ready_media cabinet not found`). This
#      is a genuine race, not deterministic -- hence the retry loop below,
#      which just re-runs the bootstrapper (a few seconds each time, the
#      541MB payload is already unpacked in the .exe's own temp dir after
#      the first run) until a `7z t` integrity check on the landed cab
#      passes clean.
#
#   3. A fresh prefix has no real fonts and defaults to Wine's XWayland
#      driver, which is bitmap-upscaled wholesale by KWin to match this
#      laptop's 125% display scale -- both combine to make the app look
#      broken even once it runs. See the detailed comments inline below
#      (font substitution, and the crisp-text-vs-working-dropdowns
#      trade-off between Wine's XWayland and native Wayland drivers).
{ pkgs, ... }:
let
  wine32 = pkgs.wine;
  winePrefix = "/home/keimoger/.local/share/wine-iiko-backoffice";
  backOfficeExe = "C:\\\\Program Files\\\\iiko\\\\iikoRMS\\\\Office\\\\BackOffice.exe";

  iikoBackofficeInstall = pkgs.writeShellApplication {
    name = "iiko-backoffice-install";
    runtimeInputs = [
      wine32
      pkgs.winetricks
      pkgs.cabextract
      pkgs.p7zip
      pkgs.unrar-free
    ];
    text = ''
      installer="''${1:-$HOME/Downloads/Setup.RMS.BackOffice.exe}"
      if [ ! -f "$installer" ]; then
        echo "iiko installer not found at: $installer" >&2
        echo "Usage: iiko-backoffice-install [/path/to/Setup.RMS.BackOffice.exe]" >&2
        exit 1
      fi

      export WINEARCH=win32
      export WINEPREFIX="${winePrefix}"
      mkdir -p "$WINEPREFIX"

      echo "==> Initializing win32 Wine prefix at $WINEPREFIX"
      wineboot -u
      timeout 30 wineserver -w || true

      echo "==> Installing .NET Framework 4.7.2 (winetricks dotnet472)"
      winetricks -q dotnet472

      # A fresh prefix ships zero real fonts (drive_c/windows/Fonts is
      # empty) -- BackOffice is a DevExpress WinForms app that asks for
      # "Segoe UI" for its default UI font. With nothing installed and no
      # substitution rule, Wine's fallback landed on whatever font it
      # happened to enumerate next after Arial in registration order,
      # which was Comic Sans MS (confirmed live via screenshot -- the
      # entire UI rendered in a comic/handwriting-style face). corefonts
      # gets real Tahoma/Arial/etc TrueType files installed; the
      # FontSubstitutes entries below are what actually route "Segoe UI"
      # requests to Tahoma instead of Wine's undefined fallback (no
      # winetricks verb installs Segoe UI itself, and Tahoma is the
      # closest metrically-compatible stand-in).
      echo "==> Installing real fonts (corefonts, tahoma) + Segoe UI -> Tahoma substitution"
      winetricks -q corefonts tahoma
      wine reg.exe add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" /v "Segoe UI" /d "Tahoma" /f
      wine reg.exe add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" /v "Segoe UI Light" /d "Tahoma" /f
      wine reg.exe add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" /v "Segoe UI Semibold" /d "Tahoma" /f

      # This laptop's display runs at 125% scale (KWin's [Xwayland]
      # Scale=1.25). Routed through the default X11/XWayland driver, all
      # of Wine's rendering is bitmap-upscaled by that same 1.25x as one
      # blanket compositor-level stretch -- inherently soft, confirmed
      # live via screenshots (fonts stayed blurry even after the fix
      # above landed correct Tahoma; trying to compensate by also
      # raising Wine's own LogPixels just doubled the stretch and made
      # it worse, not better). Wine's native Wayland driver instead
      # renders as a real Wayland client that participates in the
      # compositor's actual fractional-scale protocol directly, with no
      # bitmap stretch at all -- confirmed crisp live. "wayland,x11"
      # (rather than "x11,wayland") makes Wine prefer it unconditionally,
      # so this also covers the Start Menu shortcuts BackOffice's own
      # installer creates (winemenubuilder-generated .desktop entries
      # under ~/.local/share/applications/wine/, which call bare `wine`
      # with no DISPLAY-unset trick) -- not just the iiko-backoffice
      # wrapper below.
      #
      # Trade-off, not a free win: the Wayland driver is still
      # experimental, and its popup/grab handling has a real, currently
      # unresolved bug -- DevExpress's dropdown/combo popups open and
      # immediately close again. Wrapping the app in Wine's "virtual
      # desktop" mode fixes that specific bug under XWayland (forces
      # Wine to draw popups as internally-managed child bitmap regions
      # instead of separate compositor-level surfaces, sidestepping
      # whatever XWayland-specific compositing quirk caused the earlier,
      # different transparent-dropdown symptom) but does NOT fix it under
      # the Wayland driver -- confirmed live, both plain and
      # virtual-desktop-wrapped native-Wayland launches show the same
      # open-then-instantly-close behavior. So it's crisp text with
      # broken dropdowns (this) or working dropdowns with blurry text
      # (XWayland + virtual desktop) -- no combination tried gets both.
      # Chosen crisp-but-broken-menus per explicit preference.
      echo "==> Preferring Wine's native Wayland driver over XWayland (crisp text on this HiDPI display; trade-off is broken dropdown popups, see comment above)"
      wine reg.exe add "HKCU\Software\Wine\Drivers" /v Graphics /d wayland,x11 /f

      cache_root="$WINEPREFIX/drive_c/ProgramData/Package Cache"
      msi=""
      for attempt in 1 2 3 4 5; do
        echo "==> Running iiko bootstrapper (attempt $attempt/5) -- PosForDotNet is expected to fail here, that's fine"
        wine "$(${pkgs.coreutils}/bin/realpath "$installer")" /quiet || true
        # Bounded, not unconditional: the bootstrapper leaves background
        # helper processes (winedevice.exe etc.) running that a plain
        # `wineserver -w` can block on for a long time even though the
        # files we actually care about are already fully written -- seen
        # live taking ~15 minutes to return on an otherwise-successful
        # run. The find/7z checks below are the real synchronization.
        timeout 30 wineserver -w || true

        msi=$(find "$cache_root" -iname "iikoRMS.BackOffice.x86.msi" 2>/dev/null | head -1)
        if [ -z "$msi" ]; then
          echo "    BackOffice.x86.msi not cached yet, retrying..."
          continue
        fi
        cab="$(dirname "$msi")/RMS.Office.cab"
        if [ -f "$cab" ] && 7z t "$cab" > /dev/null 2>&1; then
          echo "    RMS.Office.cab present and verified intact."
          break
        fi
        echo "    RMS.Office.cab missing or corrupt (known Burn rollback race), retrying..."
        msi=""
      done

      if [ -z "$msi" ]; then
        echo "Failed to obtain a valid iikoRMS.BackOffice.x86.msi + RMS.Office.cab after 5 attempts." >&2
        exit 1
      fi

      echo "==> Installing BackOffice directly from $msi"
      wine msiexec /i "$(${pkgs.wine}/bin/winepath -w "$msi")" /qn
      timeout 30 wineserver -w || true

      echo "==> Done. Launch with: iiko-backoffice"
    '';
  };

  iikoBackoffice = pkgs.writeShellApplication {
    name = "iiko-backoffice";
    runtimeInputs = [ wine32 ];
    text = ''
      export WINEARCH=win32
      export WINEPREFIX="${winePrefix}"
      exec wine "${backOfficeExe}" "$@"
    '';
  };

  iikoBackofficeDesktopItem = pkgs.makeDesktopItem {
    name = "iiko-backoffice";
    desktopName = "iiko BackOffice";
    exec = "${iikoBackoffice}/bin/iiko-backoffice";
    icon = "wine";
    categories = [ "Office" ];
  };
in
{
  environment.systemPackages = [
    iikoBackofficeInstall
    iikoBackoffice
    iikoBackofficeDesktopItem

    # BackOffice's own MSI creates real Windows Start Menu shortcuts,
    # which winemenubuilder.exe mirrors into ~/.local/share/applications/
    # wine/Programs/iiko/RMS/*.desktop (iikoOffice, iikoRMS Release Notes,
    # iikoRMS Help -- more, and more naturally named, than the single
    # wrapper entry above). Their Exec= lines call bare `wine`, resolved
    # via PATH rather than any absolute store path -- confirmed live via
    # journalctl: launching them from Plasma's app launcher failed with
    # "Main process exited, code=exited, status=127/n/a" (command not
    # found), since only the wrapped iiko-backoffice/-install scripts
    # were on PATH, never plain `wine` itself. Adding it here is what
    # those auto-generated entries actually need.
    wine32
  ];
}
