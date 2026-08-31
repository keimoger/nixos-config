{ pkgs, ... }:
{
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
    options = "ctrl:nocaps";
  };

  # GNOME is the primary display manager now that GNOME is in play —
  # it assumes GDM specifically for reliable screen lock/unlock
  # (a long-standing GNOME assumption, not NixOS-specific). GDM can
  # still list Plasma as a session choice, so nothing is lost.
  services.displayManager.gdm.enable = true;
  #services.displayManager.gdm.wayland = true;

  services.desktopManager.plasma6.enable = true;
  services.displayManager.plasma-login-manager.enable = false;

  services.displayManager.sddm.enable = false;

  # These SDDM/Plasma-specific autologin PAM/systemd bits are now dead
  # config (harmless while unused, since sddm and the plasmalogin
  # greeter aren't running) — safe to delete once you've confirmed GDM
  # works for you.
  systemd.services.plasmalogin.serviceConfig.KeyringMode = "inherit";

  security.pam.services.plasmalogin-autologin.rules.auth = {
    systemd_loadkey = {
      order = 0;
      control = "optional";
      modulePath = "${pkgs.systemd}/lib/security/pam_systemd-loadkey.so";
    };
    plasmalogin = {
      order = 1;
      control = "include";
      modulePath = "plasmalogin";
    };
  };

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
