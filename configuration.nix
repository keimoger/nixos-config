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
    ./modules/fonts.nix
    ./modules/users.nix
    ./modules/plover.nix
    ./modules/packages.nix
    ./modules/vboard.nix
    ./modules/keyring.nix
    ./modules/home-manager.nix
    ./modules/iiko.nix
    ./modules/tailscale.nix
    ./modules/remote-builder.nix
    ./modules/bitwarden.nix

    # Disabled: velocity-dependent scroll momentum made sense for a
    # touchpad (never actually implemented -- raw evdev-frame data is
    # pre-gesture-recognition, so it'd need real finger-tracking math,
    # not just this) but not for a mouse wheel, where every notch is
    # the same fixed size regardless of spin speed -- a single fixed
    # scroll amount per click is the wanted behavior there. Left in
    # place (not deleted) in case touchpad inertia gets built later.
    ./modules/scroll-inertia.nix
    # Re-enabled with a rewritten plugin: the original timer-based
    # position-interpolation approach caused random ~300-500ms input
    # hangs and barely helped the actual feel. Replaced with a stateless
    # per-frame magnitude scaling approach (no timer, no interpolation) --
    # see modules/touchpad-smoothing.lua for the full reasoning, informed
    # by reverse-engineering Windows' own Synaptics driver defaults.
    ./modules/touchpad-smoothing.nix

    # Everything specific to this exact laptop (HP OmniBook Ultra Flip
    # 14-fh0013dx) lives under here -- comment out this one line to
    # deploy the rest of this config on different hardware. See
    # modules/omnibook/default.nix for what's inside.
    ./modules/omnibook
  ];

  nixpkgs.config.allowUnfree = true;

  # Root, home, and nix share one Btrfs filesystem; scrub it once monthly.
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [ "/" ];
    interval = "monthly";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data were taken. Leave this at the release
  # version of the first install of this system — do not bump it when
  # you upgrade the system itself. See configuration.nix(5).
  system.stateVersion = "26.05";
}
