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
}
