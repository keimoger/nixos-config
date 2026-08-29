{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  ploverPkg = inputs.plover-flake.packages.${system}.plover.withPlugins (plugins: [
    plugins.plover-lapwing-aio
    plugins.plover-python-dictionary
    plugins.plover-dict-commands
    plugins.plover-auto-reconnect-machine
    # plugins.plover-svg-layout-display
    plugins.plover_system_switcher
    plugins.plover-uinput
    # plugins.plover-tapey-tape
    # Add any specific plugin exposed by the flake
  ]);
in
{
  environment.systemPackages = [ ploverPkg ];

  # Autostart Plover on login, and have it start already minimized to
  # the tray (needs the AppIndicator extension from modules/gnome.nix
  # enabled once via the Extensions app — GNOME doesn't auto-enable
  # extensions just because the package is installed).
  environment.etc."xdg/autostart/plover.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Plover
    Exec=${ploverPkg}/bin/plover
    X-GNOME-Autostart-enabled=true
    NoDisplay=false
  '';
}
