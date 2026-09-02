{ pkgs, ... }:
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

  services.desktopManager.plasma6.enable = true;
  services.displayManager.plasma-login-manager.enable = false;

  # kwin-x11 is a direct, unconditional environment.systemPackages
  # entry from the plasma6 module itself (confirmed via nix why-depends
  # — nixos-system.drv -> system-path.drv -> kwin-x11.drv, 2 hops,
  # nothing transitively forcing it in). services.xserver.enable=false
  # doesn't touch it; this is the only thing that does.
  environment.plasma6.excludePackages = [ pkgs.kdePackages.kwin-x11 ];

  # Arc 140V (Lunar Lake, Xe2) is already driven by the in-kernel `xe`
  # driver + Mesa — nothing to swap there. What nixos-generate-config
  # left out is the userspace acceleration stack: iHD is the VA-API
  # backend that actually supports Xe2 (the older i965 backend doesn't),
  # vpl-gpu-rt is oneVPL/Quick Sync, intel-compute-runtime is OpenCL.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
      intel-compute-runtime
    ];
  };

  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

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
