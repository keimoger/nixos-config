{ pkgs, ... }:
let
  # SDDM's Breeze theme (theme.conf, QML, logo) ships as part of
  # plasma-desktop -- confirmed via `nix-store -q --deriver` on the
  # live /run/current-system/sw/share/sddm/themes/breeze/theme.conf,
  # NOT kdePackages.breeze (a different package, the decoration/style
  # one already patched in modules/omnibook/touch-mode-ui.nix). Its
  # background= key is just a hardcoded image path baked in at build
  # time (currently one of Breeze's own default wallpapers) -- rather
  # than patching/rebuilding plasma-desktop for a one-line image-path
  # change, this copies just the theme directory via a lightweight
  # runCommand and overwrites that one key, then adds it as an extra
  # theme via services.displayManager.sddm.extraPackages (the same
  # mechanism NixOS's own sddm module uses to make Wayland/layer-shell
  # support discoverable -- see nixos/modules/services/display-
  # managers/sddm.nix). No C++, no rebuild of anything KDE-sized.
  #
  # Copied into the repo (modules/assets/) rather than referenced at
  # its live ~/Pictures path -- flakes evaluate in pure mode, which
  # forbids reading arbitrary absolute paths outside the flake's own
  # source tree (confirmed live: "access to absolute path ... is
  # forbidden in pure evaluation mode"). Same reason
  # modules/omnibook/firmware/ish_lnlm.bin lives in-repo rather than
  # being read from wherever it was originally downloaded.
  greeterWallpaper = ./assets/greeter-wallpaper.jpeg;
  greeterTheme = pkgs.runCommand "sddm-breeze-custom-wallpaper" { } ''
    mkdir -p $out/share/sddm/themes
    cp -r ${pkgs.kdePackages.plasma-desktop}/share/sddm/themes/breeze $out/share/sddm/themes/breeze-custom-wallpaper
    chmod -R u+w $out/share/sddm/themes/breeze-custom-wallpaper
    sed -i "s|^background=.*|background=${greeterWallpaper}|" $out/share/sddm/themes/breeze-custom-wallpaper/theme.conf
  '';
in
{
  # Wayland-only: no X server. services.xserver.xkb is still the right
  # place for keyboard layout config regardless — that option tree is
  # a shared namespace NixOS reuses for Wayland compositors too, it
  # doesn't imply Xorg actually runs. SDDM's own module asserts
  # "requires either services.xserver.enable or
  # services.displayManager.sddm.wayland.enable" — satisfied below by
  # the latter, so xserver.enable can just be false outright rather
  # than working around kwin-x11 package-by-package. XWayland (for
  # individual X11 app compatibility inside the Wayland session) is
  # unaffected — programs.xwayland.enable is set unconditionally by
  # the plasma6 module, entirely independent of this.
  services.xserver.xkb = {
    layout = "us";
    variant = "";
    options = "ctrl:nocaps";
  };

  # Back to SDDM. GDM was tried specifically for its screen lock/unlock
  # reliability, but on NixOS GDM unconditionally pulls in gnome-shell
  # + mutter + gnome-session for its own greeter (nixos/modules/
  # services/display-managers/gdm.nix — "Otherwise GDM will not be
  # able to start correctly and display Wayland sessions"), completely
  # independent of whether services.desktopManager.gnome.enable is
  # set. That's not something a config toggle can route around, and it
  # meant the entire GNOME stack rebuilding alongside anything that
  # touches a shared dependency (e.g. libinput). Full GNOME removal
  # and GDM are mutually exclusive on NixOS — chose removal.
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.displayManager.sddm.wayland.compositor = "kwin";
  # extraPackages alone does NOT get merged into
  # /run/current-system/sw -- confirmed live: the greeter kept falling
  # back to the embedded stock theme ("the configured theme ... doesn't
  # exist", journalctl -u display-manager) even after a switch, because
  # ThemeDir (sw/share/sddm/themes) only reflects
  # environment.systemPackages. extraPackages is kept too since it's
  # still the documented/correct option for this, but systemPackages is
  # what actually makes the theme directory show up where sddm looks.
  services.displayManager.sddm.extraPackages = [ greeterTheme ];
  services.displayManager.sddm.theme = "breeze-custom-wallpaper";
  environment.systemPackages = [ greeterTheme ];
  services.desktopManager.lomiri.enable = true;
  services.xserver.displayManager.lightdm.enable = false;

  services.desktopManager.plasma6.enable = true;
  services.displayManager.plasma-login-manager.enable = false;

  services.displayManager.defaultSession = "plasma";

  # kwin-x11 is a direct, unconditional environment.systemPackages
  # entry from the plasma6 module itself (confirmed via nix why-depends
  # — nixos-system.drv -> system-path.drv -> kwin-x11.drv, 2 hops,
  # nothing transitively forcing it in). services.xserver.enable=false
  # doesn't touch it; this is the only thing that does.
  environment.plasma6.excludePackages = [ pkgs.kdePackages.kwin-x11 ];

  # GPU-specific acceleration packages (Arc 140V / Lunar Lake) live in
  # modules/omnibook/gpu.nix instead of here -- hardware.graphics.enable
  # itself stays here since it's the generic "turn graphics acceleration
  # on" switch any machine would want; only the GPU-model-specific
  # package choices moved out.
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  # kscreenlocker keeps whatever keyboard layout was active when the
  # screen locked. With ru+us configured (~/.config/kxkbrc LayoutList),
  # landing on the lock screen in ru meant typing the password in the
  # wrong layout whenever fingerprint auth didn't fire. KWin's
  # org.kde.screensaver /ScreenSaver interface fires an AboutToLock
  # signal just before the locker appears, so watch for it and force
  # layout index 1 (us) via org.kde.keyboard. Index is positional in
  # kxkbrc's LayoutList — update this if that list is ever reordered.
  systemd.user.services.lockscreen-english-layout = {
    description = "Force English keyboard layout when the screen locks";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "lockscreen-english-layout" ''
        ${pkgs.dbus}/bin/dbus-monitor --profile "interface='org.kde.screensaver',member='AboutToLock'" |
        while IFS=$'\t' read -r type ts serial sender dest path iface member; do
          if [ "$member" = "AboutToLock" ]; then
            ${pkgs.kdePackages.qttools}/bin/qdbus org.kde.keyboard /Layouts setLayout 1
          fi
        done
      '';
      Restart = "always";
    };
  };
}
