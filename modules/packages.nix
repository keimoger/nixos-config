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
in
{
  services.printing.enable = true;

  programs.nushell = {
    enable = true;
    autoloads = [
      atuinNuAutoload
      carapaceNuAutoload
    ];
  };
  programs.atuin.enable = true;

  powerManagement.powertop.enable = true;

  environment.systemPackages = with pkgs; [
    sbctl
    git
    helix
    nixd
    nixfmt
    carapace
  ];
}
