{ pkgs, ... }:
{
  users.users."keimoger" = {
    isNormalUser = true;
    description = "Kei Moger";
    shell = pkgs.nushell;
    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
      "uinput"
      "dialout"
    ];
    packages = with pkgs; [
      spotify
      # ~/.config/google-chrome-flags.conf (previously used for this) is
      # a Debian/Ubuntu-specific launcher convention -- confirmed nixpkgs'
      # own generated wrapper never reads it at all (checked the actual
      # exec line). commandLineArgs is the real mechanism: nixpkgs'
      # package.nix unconditionally appends it via --add-flags.
      #
      # --ozone-platform-hint=auto: without this, Chrome runs as a plain
      # XWayland client despite being on a Wayland session (confirmed
      # live: NIXOS_OZONE_WL, which the wrapper's own conditional ozone
      # flag depends on, was never set anywhere -- the previous "fix"
      # for this was the same non-functional flags file). XWayland
      # converts libinput's continuous scroll deltas into discrete X11
      # wheel-click events, which is why scrolling felt chunky in Chrome
      # specifically and nowhere else.
      # --disable-smooth-scrolling: Chrome's own built-in wheel-scroll
      # easing animation, which was stacking on top of
      # modules/scroll-inertia.nix's synthetic decaying scroll events.
      (google-chrome.override {
        commandLineArgs = "--ozone-platform-hint=auto --disable-smooth-scrolling";
      })
      thunderbird
      claude-code
      pkgs.orca-slicer
      bitwarden-desktop
      vscode
      telegram-desktop
      pkgs.krita
    ];
  };

  hardware.uinput.enable = true;
  users.groups.uinput = { };

  services.udev.extraRules = ''
    KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0666", TAG+="uaccess"
  '';
}
