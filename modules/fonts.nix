{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    dejavu_fonts
    cantarell-fonts
    liberation_ttf
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font" "DejaVu Sans Mono" ];
      sansSerif = [ "Cantarell" "Noto Sans" ];
      serif = [ "Noto Serif" "DejaVu Serif" ];
    };
  };

  environment.pathsToLink = [ "/share/icons" ];
  environment.systemPackages = with pkgs; [
    hicolor-icon-theme
    adwaita-icon-theme
  ];
}
