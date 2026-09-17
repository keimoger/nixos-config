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

  # `{:altcase:<letter>}` / `{:altcase_retro}` metas: alternating-case
  # fingerspelling glue (sOmEtHiNg) alongside Lapwing's existing -FPLT/*FPLT
  # (case glue) and -RBGS (stitch) suffixes, plus a retroactive re-case of
  # the last word via the bare -RBLT stroke. See ~/projects/plover-altcase
  # and plover/altcase.json.
  plover-altcase = pkgs.python3Packages.buildPythonPackage {
    pname = "plover-altcase";
    version = "0.1.0";
    src = inputs.plover-altcase;
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
    plugins.plover-tapey-tape
    # Add any specific plugin exposed by the flake
    plover-russian-firebird
    plover-altcase
  ]);
in
{
  environment.systemPackages = [ ploverPkg ];

  # Autostart Plover on login, and have it start already minimized to
  # the tray (needs the AppIndicator extension from modules/gnome.nix
  # enabled once via the Extensions app — GNOME doesn't auto-enable
  # extensions just because the package is installed).
  #
  # NOTE: PLOVER_UINPUT_LAYOUT=ru was tried here to fix unreliable
  # Cyrillic/punctuation output (plover-uinput falls back to a
  # Ctrl+Shift+U Unicode-injection sequence for any character outside
  # the active layout's scancode table, which silently leaks its hex
  # digits as plain text when no ibus/fcitx5 daemon is running to catch
  # it — confirmed directly, not a plugin bug). Reverted: layout="ru"
  # removes Latin letters from the fast path entirely (confirmed empty
  # for a-z), which broke Lapwing — the primary, daily-use system —
  # far worse than the Russian issue it was meant to fix. Do not
  # re-apply without first getting an ibus/fcitx5 daemon actually
  # running and wired into GTK_IM_MODULE/QT_IM_MODULE/XMODIFIERS, so
  # the Unicode-injection fallback works for whichever layout ISN'T
  # covered by the fast path, instead of picking one language to break.
  environment.etc."xdg/autostart/plover.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Plover
    Exec=${ploverPkg}/bin/plover
    X-GNOME-Autostart-enabled=true
    NoDisplay=false
  '';
}
