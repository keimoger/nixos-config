{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  basePlover = inputs.plover-flake.packages.${system}.plover;

  # Not in the plover_plugins_registry (it's unpublished/local), so it can't
  # come from `withPlugins`'s own plugin set like the others below — built
  # here the same way plover-flake builds every registry plugin, just from
  # the local `path:` input instead of a PyPI tarball. Picks up live edits
  # on every rebuild since `path:` inputs aren't commit-locked.
  plover-russian-firebird = pkgs.python3Packages.buildPythonPackage {
    pname = "plover-russian-firebird";
    version = "0.0.7";
    src = inputs.plover-russian-firebird;
    pyproject = true;
    build-system = [ pkgs.python3Packages.setuptools ];
    buildInputs = [ basePlover ];
  };

  ploverPkg = basePlover.withPlugins (plugins: [
    plugins.plover-lapwing-aio
    plugins.plover-python-dictionary
    plugins.plover-dict-commands
    plugins.plover-auto-reconnect-machine
    # plugins.plover-svg-layout-display
    plugins.plover_system_switcher
    plugins.plover-uinput
    # plugins.plover-tapey-tape
    # Add any specific plugin exposed by the flake
    plover-russian-firebird
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
