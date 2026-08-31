{ pkgs, ... }:
let
  # `atuin init nu` just prints a static script derived from the atuin
  # binary itself, so generating it at build time keeps it pinned to
  # whatever atuin version this nixpkgs revision carries.
  atuinNuAutoload = pkgs.runCommand "atuin-nu-autoload" { } ''
    export HOME=$TMPDIR
    mkdir -p $out/share/nushell/vendor/autoload
    ${pkgs.atuin}/bin/atuin init nu > $out/share/nushell/vendor/autoload/atuin.nu
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
      carapaceNuAutoload
      nixShellPkgNuAutoload
    ];
  };
  programs.atuin.enable = true;

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
    helix
    nixd
    nixfmt
    carapace
    openlogi
  ];
}
