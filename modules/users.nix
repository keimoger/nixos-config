{ pkgs, ... }:
{
  # See modules/davinci-resolve-package.nix for why this is needed --
  # nixpkgs' own pinned download hash for it is currently stale.
  # nixpkgs.overlays = [
  #   (final: prev: {
  #     davinci-resolve = final.callPackage ./davinci-resolve-package.nix { };
  #   })
  # ];

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
      # Forces XWayland instead of native Wayland. This display runs at
      # 125% (fractional) scaling (confirmed via kwinoutputconfig.json
      # / KWin's own support info) -- native KDE/Qt apps handle that
      # fine, but Telegram's own custom QRhi-based rendering doesn't
      # cooperate well with Wayland's fractional-scale protocol and
      # falls into a much more expensive internal rescale path,
      # tanking to ~3fps. Confirmed live: a one-off `QT_QPA_PLATFORM=
      # xcb telegram-desktop` run stayed smooth, while the normal
      # (native Wayland) launch stays janky no matter how long it's
      # been running. XWayland clients render at a clean 1x and let
      # the compositor do one cheap GPU-composited scale of the whole
      # window instead, sidestepping the app's own scaling entirely.
      (telegram-desktop.overrideAttrs (old: {
        qtWrapperArgs = (old.qtWrapperArgs or [ ]) ++ [
          "--set"
          "QT_QPA_PLATFORM"
          "xcb"
        ];
      }))
      pkgs.krita
      # davinci-resolve
    ];
  };

  hardware.uinput.enable = true;
  users.groups.uinput = { };

  services.udev.extraRules = ''
    KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
  '';

  # Grant raw HID access to the active local session, rather than every
  # local user. Run before systemd's 73-seat-late.rules applies the ACL.
  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "local-hidraw-access";
      destination = "/etc/udev/rules.d/70-local-hidraw.rules";
      text = ''
        SUBSYSTEM=="hidraw", KERNEL=="hidraw*", MODE="0660", TAG+="uaccess"
      '';
    })
  ];
}
