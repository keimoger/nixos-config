{ pkgs, ... }:
let
  cascadiaFonts = pkgs.stdenvNoCC.mkDerivation {
    pname = "cascadia-local-fonts";
    version = "2026-10-07";
    src = ../assets/cascadia-fonts;
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/share/fonts/truetype/cascadia
      cp $src/*.ttf $out/share/fonts/truetype/cascadia/
    '';
  };
  playfairFonts = pkgs.stdenvNoCC.mkDerivation {
    pname = "playfair-display-local-fonts";
    version = "2025-09-11";
    src = ../assets/playfair-fonts;
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/share/fonts/truetype/playfair-display
      cp $src/*.ttf $out/share/fonts/truetype/playfair-display/
    '';
  };
  timesNewRomanFonts = pkgs.stdenvNoCC.mkDerivation {
    pname = "times-new-roman-local-fonts";
    version = "2022-02-05";
    src = ../assets/times-new-roman;
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/share/fonts/truetype/times-new-roman
      cp $src/*.ttf $out/share/fonts/truetype/times-new-roman/
    '';
  };
in
{
  fonts.packages = with pkgs; [
    cascadiaFonts
    playfairFonts
    timesNewRomanFonts
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
      monospace = [
        "Cascadia Code"
        "Cascadia Mono"
        "JetBrainsMono Nerd Font"
        "DejaVu Sans Mono"
      ];
      sansSerif = [
        "Cantarell"
        "Noto Sans"
      ];
      serif = [
        "Playfair Display"
        "Times New Roman"
        "Noto Serif"
        "DejaVu Serif"
      ];
    };
    subpixel.lcdfilter = "none";
    # lcdfilter=none alone only disables the color-fringe-reduction
    # filter -- it doesn't stop fontconfig assuming a subpixel
    # geometry in the first place. Live check (`fc-match -v`) showed
    # rgba=4 (VBGR, vertical BGR) actively configured on this system
    # with the filter already off -- an unrelated default/heuristic,
    # not anything set here, and almost certainly wrong for this exact
    # panel regardless of what its real subpixel layout is: this is a
    # Wayland session running at a fractional 1.25x scale (`kscreen-
    # doctor -o`), which breaks subpixel-positioned rendering on its
    # own since the compositor scales/composites window content as
    # textures -- independent of the OLED point that motivated
    # checking this in the first place (some OLED panels use non-RGB-
    # stripe subpixel arrangements entirely, where standard ClearType-
    # style subpixel AA is simply wrong). "none" here commits fully to
    # plain grayscale antialiasing, which is correct either way.
    subpixel.rgba = "none";
  };

  environment.pathsToLink = [ "/share/icons" ];
  environment.systemPackages = with pkgs; [
    hicolor-icon-theme
    adwaita-icon-theme
  ];
}
