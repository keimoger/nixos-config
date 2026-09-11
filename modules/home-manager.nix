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

        # The lock screen (kscreenlocker) and the SDDM greeter
        # (modules/desktop.nix) are two entirely separate components
        # with independent wallpaper config -- confirmed live: after
        # fixing the greeter, the *lock screen* was still showing
        # Breeze's stock wallpaper (~/.config/kscreenlockerrc didn't
        # even exist -- no override had ever been set, defaulting to
        # whatever's baked into the lock screen's own QML). Same source
        # image as the greeter/desktop wallpaper, reused via a relative
        # path since this file lives in the same modules/ directory.
        kscreenlocker.appearance.wallpaper = ./assets/greeter-wallpaper.jpeg;

        # Meta+Ctrl+Arrow already does grid-aware desktop switching by
        # default in KWin — this is only kept for anything still relying
        # on the linear next/previous actions.
        shortcuts.kwin = {
          "Switch to Next Desktop" = "Ctrl+Alt+Right";
          "Switch to Previous Desktop" = "Ctrl+Alt+Left";

          # macOS-style Cmd+Q: graceful quit, not a force-kill. KWin's
          # "Window Close" action (display name "Close Window",
          # confirmed via ~/.config/kglobalshortcutsrc's internal key)
          # sends the focused window a normal close request -- same as
          # clicking its close button, so apps can still prompt to
          # save unsaved work -- not "Kill Window" (KWin's actual
          # xkill-style forceful terminate-with-no-warning action).
          # Alt+F4 kept alongside it rather than replaced, since a
          # single string value here overwrites the whole active-keys
          # list rather than adding to it.
          "Window Close" = [
            "Alt+F4"
            "Meta+Q"
          ];
        };

        # Meta+Q was already KDE's own stock default for this
        # (plasmashell's "manage activities" / Activity Switcher, not
        # something configured deliberately in this config) -- cleared
        # so it doesn't fight with Close Window above for the same key.
        shortcuts.plasmashell."manage activities" = "none";

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

        # Media-key/slider volume step, KConfigXT-backed (verified via
        # KDE/plasma-pa's globalconfig.kcfg: VolumeStep, [General],
        # default 5) — a real setting, unlike the brightness step (see
        # below), which is a hardcoded algorithm with no config hook at
        # all. configFile is plasma-manager's generic [file][group][key]
        # escape hatch for settings with no typed option of their own;
        # it patches this one key in ~/.config/plasmaparc without
        # touching the unrelated mic-mute settings already stored there.
        configFile."plasmaparc"."General"."VolumeStep" = 1;

        # Touchpad scroll was rough/jumpy -- root cause found in
        # ~/.config/kcminputrc: ScrollFactor was 4 for this exact
        # touchpad (group keyed by its actual vendor/product ID in
        # decimal, 1739/53202 = 0x06CB/0xCFD2, same hardware as the
        # haptic control elsewhere in modules/omnibook/touchpad.nix).
        # KWin's libinput backend (src/backends/libinput/events.cpp)
        # does `libinput_event_pointer_get_scroll_value(...) *
        # device()->scrollFactor()` on every single scroll event, and
        # scrollFactor()'s compiled-in default is 1.0 -- so every
        # scroll motion (and any raw jitter riding along with it) was
        # being amplified 4x. Brought down to 2x: still faster than
        # stock, but halves the amplification of both speed and
        # roughness.
        # "/" in the group name (not "[...][...]") is plasma-manager's
        # own separator for nested KDE config groups -- see plasma-
        # manager's script/write_config.py, which reconstructs the
        # bracket-chain form ([Libinput][1739][53202][...]) from it.
        configFile."kcminputrc"."Libinput/1739/53202/SYNA3580:00 06CB:CFD2 Touchpad"."ScrollFactor" = 2.0;
      };

      home.stateVersion = "26.05";

      # google-chrome (modules/users.nix) is a plain unwrapped package
      # with no Wayland opt-in, so it runs as an XWayland client by
      # default even on this Wayland-only session (modules/desktop.nix)
      # -- XWayland translates the touchpad's continuous libinput
      # scroll deltas into synthetic X11 wheel-click events, which is
      # inherently steppy, rather than passing through real per-pixel
      # motion the way a native Wayland client (every KDE/Qt app here)
      # gets. This is why scrolling only felt chunky in Chrome
      # specifically, unconditionally, regardless of the KWin-level
      # ScrollFactor fix above (which only rescales whatever KWin
      # itself receives -- irrelevant to an XWayland/X11 client, which
      # never goes through KWin's own libinput axis handling at all).
      # Chrome reads flags (one per line, no leading --stripping
      # needed) from this exact path -- ozone-platform-hint=auto makes
      # it detect the Wayland session and connect as a native client
      # instead, restoring real continuous scroll deltas.
      xdg.configFile."google-chrome-flags.conf".text = ''
        --ozone-platform-hint=auto
      '';

      # This is the actual root cause of every "fonts look like ass"
      # complaint this whole session, on both the host system and every
      # Wine app tested (Telegram, iiko BackOffice) -- a per-user
      # fontconfig override, apparently written by KDE's own Fonts KCM
      # at some point in the past (no NixOS/home-manager management, no
      # generation marker, plain hand/GUI-authored XML), hardcoding
      # rgba=vbgr with mode="assign" -- a forceful match rule that wins
      # over anything modules/fonts.nix's system-level subpixel.rgba
      # option could ever set, no matter its value. Confirmed live via
      # `fc-match -v sans` before and after: rgba 4(vbgr) -> 5(none).
      # Bringing it under home-manager (rather than just hand-editing
      # the live file, which is what actually fixed it in the moment)
      # is what keeps it from silently drifting back -- e.g. if the
      # Fonts KCM ever gets touched again, or on a fresh account.
      xdg.configFile."fontconfig/fonts.conf".text = ''
        <?xml version='1.0'?>
        <fontconfig>
         <match target="pattern">
          <edit mode="assign" name="rgba">
           <const>none</const>
          </edit>
         </match>
         <match target="pattern">
          <edit mode="assign" name="hinting">
           <bool>true</bool>
          </edit>
         </match>
         <match target="pattern">
          <edit mode="assign" name="hintstyle">
           <const>hintslight</const>
          </edit>
         </match>
         <dir>~/.local/share/fonts</dir>
         <match target="pattern">
          <edit mode="assign" name="antialias">
           <bool>true</bool>
          </edit>
         </match>
        </fontconfig>
      '';

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
      # update). Directions are intentionally reversed, and Click opens
      # KWin's Grid View effect (desktop-grid overview, closer to macOS
      # Mission Control than "Overview", which is per-window instead of
      # per-desktop) per preference, not the map's literal direction names.
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
        Click = { RunShellCommand = "/run/current-system/sw/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut 'Grid View'" }

        BINDINGS
                  ${pkgs.coreutils}/bin/tail -n "+$((endLine + 1))" "$configFile"; } > "$configFile.new" && mv "$configFile.new" "$configFile"
                fi
              fi
      '';
    };
}
