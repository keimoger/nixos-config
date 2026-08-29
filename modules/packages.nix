{ pkgs, ... }:
{
  services.printing.enable = true;

  programs.nushell.enable = true;

  environment.systemPackages = with pkgs; [
    sbctl
    git
    helix
    ghostty
  ];
}
