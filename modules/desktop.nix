{ pkgs, ... }:
{
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
    options = "ctrl:nocaps";
  };

  # GNOME is explicitly off; Plasma 6 is the desktop in use.
  services.displayManager.gdm.enable = false;
  services.desktopManager.gnome.enable = false;

  services.desktopManager.plasma6.enable = true;
  services.displayManager.plasma-login-manager.enable = false;

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

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
