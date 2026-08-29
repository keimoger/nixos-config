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
  services.displayManager.gdm.wayland = true;

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

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
