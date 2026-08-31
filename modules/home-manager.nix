# home-manager, integrated as a NixOS module (not run standalone) so it
# shares the system's pkgs and profile instead of maintaining its own.
{ inputs, ... }:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  # Written as a function (not a bare attrset) so lib/pkgs here are
  # home-manager's own module args — needed for lib.hm.dag.entryAfter
  # below, which doesn't exist on the outer NixOS-level lib.
  home-manager.users."keimoger" =
    { pkgs, lib, ... }:
    {
      imports = [ inputs.plasma-manager.homeModules.plasma-manager ];

    programs.plasma = {
      enable = true;

      # Meta+Ctrl+Arrow already does grid-aware desktop switching by
      # default in KWin — this is only kept for anything still relying
      # on the linear next/previous actions.
      shortcuts.kwin = {
        "Switch to Next Desktop" = "Ctrl+Alt+Right";
        "Switch to Previous Desktop" = "Ctrl+Alt+Left";
      };

      # List order sets which layout is default/first (kxkbrc
      # LayoutList). Was ru,us — ru being first meant a fresh login
      # session, the lock screen, and Plover's plover_uinput extension
      # (which reads LayoutList directly rather than the live-active
      # layout) all defaulted to Russian. us first fixes all three at
      # once; the caps:ctrl_modifier option is carried over so it's
      # not lost when this replaces kxkbrc's Options line wholesale.
      input.keyboard = {
        layouts = [
          { layout = "us"; }
          { layout = "ru"; }
        ];
        options = [ "caps:ctrl_modifier" ];
      };
    };

    home.stateVersion = "26.05";

    # OpenLogi (~/.config/openlogi/config.toml) has no NixOS/home-manager
    # module, and it's not a file we can just overwrite wholesale — most
    # of it (identity, capabilities, model_info) is hardware state the
    # app discovers and persists for this exact mouse, not config we
    # authored. So this patches only the GestureButton bindings block in
    # place by line range, byte-identical elsewhere, rather than round
    # -tripping the whole file through a TOML library (verified: that
    # reformats inline tables into full [section] headers and collapses
    # arrays — technically equivalent TOML, but an untested surface to
    # risk for zero benefit here).
    #
    # These call KWin's grid-aware "Switch One Desktop <dir>" actions
    # directly via qdbus rather than injecting keystrokes — OpenLogi's
    # own presets (NextDesktop, MissionControl, ...) are macOS actions
    # translated to Linux key combos that don't match any KDE default,
    # and the Linux GUI doesn't expose custom keybinding for gesture
    # directions (only RunShellCommand/CustomShortcut, found by reading
    # the agent binary — undocumented, may not survive an OpenLogi
    # update). Directions are intentionally reversed and Click opens
    # KWin's Overview effect (the closest match to macOS Mission
    # Control) per preference, not the map's literal direction names.
    home.activation.openlogiGestureBindings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      configFile="$HOME/.config/openlogi/config.toml"
      if [ -f "$configFile" ]; then
        startLine=$(${pkgs.gnugrep}/bin/grep -n '^\[devices\."direct:046d:b042:serial:2543apyjhv18"\.bindings\.GestureButton\]$' "$configFile" | ${pkgs.coreutils}/bin/cut -d: -f1)
        if [ -n "$startLine" ]; then
          endLine=$(${pkgs.coreutils}/bin/tail -n "+$((startLine + 1))" "$configFile" | ${pkgs.gnugrep}/bin/grep -n '^\[' | ${pkgs.coreutils}/bin/head -1 | ${pkgs.coreutils}/bin/cut -d: -f1)
          if [ -n "$endLine" ]; then
            endLine=$((startLine + endLine - 1))
          else
            endLine=$(${pkgs.coreutils}/bin/wc -l < "$configFile")
          fi
          { ${pkgs.coreutils}/bin/head -n "$startLine" "$configFile"; cat <<'BINDINGS'
Up = { RunShellCommand = "/run/current-system/sw/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut 'Switch One Desktop Down'" }
Down = { RunShellCommand = "/run/current-system/sw/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut 'Switch One Desktop Up'" }
Left = { RunShellCommand = "/run/current-system/sw/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut 'Switch One Desktop to the Right'" }
Right = { RunShellCommand = "/run/current-system/sw/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut 'Switch One Desktop to the Left'" }
Click = { RunShellCommand = "/run/current-system/sw/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut 'Overview'" }

BINDINGS
          ${pkgs.coreutils}/bin/tail -n "+$((endLine + 1))" "$configFile"; } > "$configFile.new" && mv "$configFile.new" "$configFile"
        fi
      fi
    '';
  };
}
