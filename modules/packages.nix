{ pkgs, ... }:
let
  # `atuin init nu` just prints a static script derived from the atuin
  # binary itself, so generating it at build time keeps it pinned to
  # whatever atuin version this nixpkgs revision carries.
  atuinNuAutoload = pkgs.runCommand "atuin-nu-autoload" { } ''
    export HOME=$TMPDIR
    mkdir -p $out/share/nushell/vendor/autoload
    ${pkgs.atuin}/bin/atuin init nu > $out/share/nushell/vendor/autoload/atuin.nu

    # `atuin init nu` (still true as of 18.19.0) defines two separate
    # keybindings -- Ctrl+R search and Up-arrow search -- both literally
    # named "atuin" instead of unique names, which nushell warns about
    # on every startup ("Multiple keybindings share a name"). Cosmetic
    # only (both bindings still work either way, per nushell's own
    # warning text), but trivial to fix here since this script is
    # already regenerated and pinned at build time.
    ${pkgs.perl}/bin/perl -0777 -pi -e '
      s/name: atuin(\s*\n\s*modifier: control)/name: atuin_ctrl_r$1/;
      s/name: atuin(\s*\n\s*modifier: none)/name: atuin_up$1/;
    ' $out/share/nushell/vendor/autoload/atuin.nu
  '';

  # Nushell prints a startup banner (version, tips, GitHub link) by
  # default -- this is its own documented off switch.
  noBannerNuAutoload = pkgs.writeTextDir "share/nushell/vendor/autoload/no-banner.nu" ''
    $env.config.show_banner = false
  '';

  carapaceNuAutoload = pkgs.writeTextDir "share/nushell/vendor/autoload/carapace.nu" ''
    $env.config.completions.external = {
        enable: true
        completer: {|spans| carapace $spans.0 nushell ...$spans | from json }
    }
  '';

  # `nix-shell -p foo` always drops into bash, ignoring $SHELL — a long
  # standing nix-shell quirk, not fixable via config. `nix shell
  # nixpkgs#foo` (the modern CLI) execs $SHELL properly and stays in
  # nu, so this just restores the old `-p pkg1 pkg2` ergonomics on top
  # of it: `nsp foo bar` -> `nix shell nixpkgs#foo nixpkgs#bar`.
  nixShellPkgNuAutoload = pkgs.writeTextDir "share/nushell/vendor/autoload/nsp.nu" ''
    def nsp [...pkgs: string] {
        nix shell ...($pkgs | each {|p| $"nixpkgs#($p)" })
    }
  '';
in
{
  services.printing.enable = true;

  programs.nushell = {
    enable = true;
    autoloads = [
      atuinNuAutoload
      noBannerNuAutoload
      carapaceNuAutoload
      nixShellPkgNuAutoload
    ];
  };
  programs.atuin.enable = true;
  # The NixOS module unconditionally points atuin at ATUIN_CONFIG_DIR=
  # /etc/atuin (atuin only reads that or XDG_CONFIG_HOME, not
  # XDG_CONFIG_DIRS), but only actually writes /etc/atuin/config.toml
  # when settings is non-empty (nixos/modules/programs/atuin.nix:
  # `lib.mkIf (cfg.settings != { })`). We never set .settings, so the
  # file never existed — every atuin invocation was pointed at a
  # config path with nothing there (`atuin status` errored outright:
  # "failed to create file /etc/atuin/config.toml: No such file or
  # directory"), and since daemon.enable also defaults to true on
  # Linux, the daemon was very likely failing on the same missing file
  # — together showing up as history search "partially" broken rather
  # than a clean failure. fuzzy is also just a better default than
  # atuin's own "prefix" for interactive Up-arrow search.
  programs.atuin.settings = {
    search_mode = "fuzzy";
  };

  # VS Code extensions (and similar tools) sometimes bundle a prebuilt
  # dynamically-linked Linux binary that expects the standard FHS
  # /lib64/ld-linux-x86-64.so.2 loader path, which NixOS doesn't have
  # (e.g. the Claude Code VS Code extension's native-binary/claude).
  # nix-ld provides that stub loader system-wide so such binaries run
  # unmodified. https://nix.dev/permalink/stub-ld
  programs.nix-ld.enable = true;

  hardware.intel-gpu-tools.enable = true;

  # openlogi is a plain package, not a NixOS module, so its udev rules
  # (hidraw + mouse evdev-node access for Logitech's HID++ devices) and
  # its systemd --user agent unit need to be pulled in explicitly.
  # openlogi's udev rules live at the conventional lib/udev/rules.d/,
  # so services.udev.packages picks them up fine. Its systemd user unit
  # is instead shipped at share/systemd/user/ (not lib/systemd/user/,
  # the path systemd.packages actually scans), so it's never imported
  # that way — defining the service directly here, mirroring the
  # package's own unit file, actually works instead.
  services.udev.packages = [ pkgs.openlogi ];
  systemd.user.services.openlogi-agent = {
    description = "OpenLogi background agent (Logitech HID++ device control)";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.openlogi}/bin/openlogi-agent";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  environment.systemPackages = with pkgs; [
    sbctl
    git
    gh
    helix
    nixd
    nixfmt
    carapace
    openlogi
    btop
    anydesk
    nix-output-monitor
    jetbrains.idea
    android-studio
  ];

  # btop's own "show_cpu_watts" (on by default) reads
  # /sys/class/powercap/intel-rapl:0/energy_uj directly (confirmed in
  # its source, src/linux/btop_collect.cpp) -- confirmed live this file
  # is root-only (-r--------), so it silently comes up blank for a
  # normal user. btop's own Makefile documents the fix: grant the
  # binary these two capabilities instead of full setuid/sudo.
  # /run/wrappers/bin is ahead of the regular profile in PATH, so
  # plain `btop` picks up this wrapped version automatically.
  security.wrappers.btop = {
    owner = "root";
    group = "root";
    capabilities = "cap_dac_read_search,cap_perfmon=+ep";
    source = "${pkgs.btop}/bin/btop";
  };
}
