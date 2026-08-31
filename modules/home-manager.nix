# home-manager, integrated as a NixOS module (not run standalone) so it
# shares the system's pkgs and profile instead of maintaining its own.
{ inputs, ... }:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users."keimoger" = {
    imports = [ inputs.plasma-manager.homeManagerModules.plasma-manager ];

    programs.plasma = {
      enable = true;

      # OpenLogi's gesture-button "Left"/"Right" actions inject
      # Ctrl+Alt+Left/Right (the GNOME/Unity desktop-switch combo) —
      # KDE has no default binding for that, so the swipe did nothing.
      # These match the mouse's own keystrokes rather than the other
      # way around, since OpenLogi doesn't expose that binding as
      # configurable on the Linux port yet.
      shortcuts.kwin = {
        "Switch to Next Desktop" = "Ctrl+Alt+Right";
        "Switch to Previous Desktop" = "Ctrl+Alt+Left";
      };
    };

    home.stateVersion = "26.05";
  };
}
