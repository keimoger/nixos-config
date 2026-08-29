{ pkgs, ... }:
{
  services.printing.enable = true;

  programs.nushell.enable = true;
  programs.atuin.enable = true;

  environment.systemPackages = with pkgs; [
    sbctl
    git
    helix
    nixd
    nixfmt
  ];
}
