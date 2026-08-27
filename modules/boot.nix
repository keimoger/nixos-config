{ ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Secure Boot via lanzaboote. It builds on top of systemd-boot, so
  # systemd-boot itself stays "enabled" for its generation-management
  # options, but its own bootloader install step is disabled in favor
  # of lanzaboote's signed one.
  boot.loader.systemd-boot = {
    enable = false;
    configurationLimit = 3; # keep only the 3 latest generations in /boot
  };
  boot.loader.efi.canTouchEfiVariables = true;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 3;
  };

  boot.initrd.systemd.enable = true;
}
