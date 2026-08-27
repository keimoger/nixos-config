# Entry point for the system. Keep this file thin: it should only wire
# together the hardware scan and the topic-based modules below. Anything
# host-specific that doesn't fit a module cleanly can live here at the
# bottom (currently just system.stateVersion).
{ ... }:
{
  imports = [
    ./hardware-configuration.nix

    ./modules/boot.nix
    ./modules/networking.nix
    ./modules/locale.nix
    ./modules/desktop.nix
    ./modules/audio.nix
    ./modules/bluetooth.nix
    ./modules/security.nix
    ./modules/sensors.nix
    ./modules/fonts.nix
    ./modules/users.nix
    ./modules/plover.nix
    ./modules/packages.nix
  ];

  nixpkgs.config.allowUnfree = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data were taken. Leave this at the release
  # version of the first install of this system — do not bump it when
  # you upgrade the system itself. See configuration.nix(5).
  system.stateVersion = "26.05";
}
