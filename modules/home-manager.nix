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
          # Both bindings kept rather than one replacing the other:
          # Ctrl+Alt+Right/Left was already set here deliberately (see
          # below), Meta+Alt+L/H came from a friend's exported shortcut
          # scheme (~/Desktop/keiboardshortcuts.kksrc) -- either combo
          # now triggers the same action.
          "Switch to Previous Desktop" = [
            "Ctrl+Alt+Left"
            "Meta+Alt+H"
          ];

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

          # Cleared stock defaults that collided with imported/Krohnkite
          # bindings on the exact same key (found by diffing every bound
          # key in the live kglobalshortcutsrc for duplicates):
          #   - "Overview" (native KWin action) vs "Cycle Overview"
          #     below, both Meta+W -- keeping Cycle Overview.
          #   - "Show Desktop" vs plasmashell's "activate application
          #     launcher", both Meta+D -- keeping the launcher.
          #   - KrohnkiteTileLayout vs KrohnkiteStairLayout below, both
          #     Meta+T -- Krohnkite ships Tile=Meta+T as its own built-in
          #     default, which doesn't get cleared just because a
          #     different Krohnkite action was separately bound to the
          #     same key -- keeping Stair (the deliberately-imported one).
          "Overview" = "none";
          "Show Desktop" = "none";
          "KrohnkiteTileLayout" = "none";

          # --- everything below imported from a friend's exported KDE
          # shortcut scheme (~/Desktop/keiboardshortcuts.kksrc) ---
          "Activate Window Demanding Attention" = "Meta+Ctrl+A";
          "Cube" = "Meta+C";
          "Cycle Overview" = "Meta+W";
          "Decrease Opacity" = "Meta+Ctrl+-";
          "Expose" = "Ctrl+F9";
          "ExposeAll" = [
            "Launch (C)"
            "Ctrl+F10"
          ];
          "ExposeClass" = "Ctrl+F7";
          "Grid View" = "Meta+G";
          "Increase Opacity" = "Meta+Ctrl+=";
          "Kill Window" = "Meta+Ctrl+Esc";
          "MoveMouseToCenter" = "Meta+F6";
          "MoveMouseToFocus" = "Meta+F5";
          "ShowDesktopGrid" = "Meta+F8";
          "Suspend Compositing" = "Alt+Shift+F12";
          "Switch One Desktop Down" = "Meta+Ctrl+Down";
          "Switch One Desktop Up" = "Meta+Ctrl+Up";
          "Switch One Desktop to the Left" = "Meta+Ctrl+Left";
          "Switch One Desktop to the Right" = "Meta+Ctrl+Right";
          "Switch Window Down" = "Meta+Alt+Down";
          "Switch Window Left" = "Meta+Alt+Left";
          "Switch Window Right" = "Meta+Alt+Right";
          "Switch Window Up" = "Meta+Alt+Up";
          "Switch to Desktop 1" = "Meta+1";
          "Switch to Desktop 2" = "Meta+2";
          "Switch to Desktop 3" = "Meta+3";
          "Switch to Desktop 4" = "Meta+4";
          "Switch to Desktop 5" = "Meta+5";
          "Switch to Desktop 6" = "Meta+6";
          "Switch to Desktop 7" = "Meta+7";
          "Switch to Desktop 8" = "Meta+8";
          "Switch to Desktop 9" = "Meta+9";
          "Walk Through Windows" = "Alt+Tab";
          "Walk Through Windows (Reverse)" = "Alt+Shift+Tab";
          "Walk Through Windows of Current Application" = "Alt+`";
          "Walk Through Windows of Current Application (Reverse)" = "Alt+~";
          "Window Minimize" = "Meta+PgDown";
          "Window One Desktop Down" = "Meta+Ctrl+Shift+Down";
          "Window One Desktop Up" = "Meta+Ctrl+Shift+Up";
          "Window One Desktop to the Left" = [
            "Meta+Ctrl+Shift+Left"
            "Meta+Ctrl+Shift+H"
          ];
          "Window One Desktop to the Right" = [
            "Meta+Ctrl+Shift+L"
            "Meta+Ctrl+Shift+Right"
          ];
          "Window One Screen Down" = "Meta+Ctrl+Shift+J";
          "Window Operations Menu" = "Alt+F3";
          "Window Quick Tile Top Right" = "Meta+Shift+O";
          "Window Restore" = "Meta+Backspace";
          "Window to Desktop 1" = "Meta+!";
          "Window to Desktop 2" = "Meta+@";
          "Window to Desktop 3" = "Meta+#";
          "Window to Desktop 4" = "Meta+$";
          "Window to Desktop 5" = "Meta+%";
          "Window to Desktop 6" = "Meta+^";
          "Window to Desktop 7" = "Meta+&";
          "Window to Desktop 8" = "Meta+*";
          "Window to Desktop 9" = "Meta+(";
          "Window to Next Screen" = "Meta+Shift+Right";
          "Window to Previous Screen" = "Meta+Shift+Left";
          "disableInputCapture" = "Meta+Shift+Esc";
          "view_zoom_in" = [
            "Meta+="
            "Meta++"
          ];
          "view_zoom_out" = "Meta+-";

          # Krohnkite (dynamic tiling KWin script -- installed via
          # home.packages below, enabled via the kwinrc Plugins entry
          # further down). Also from the friend's exported scheme.
          "KrohnkiteDecrease" = "Meta+Shift+I";
          "KrohnkiteFloatAll" = "Meta+Shift+F";
          "KrohnkiteFocusDown" = "Meta+J";
          "KrohnkiteFocusLeft" = "Meta+H";
          "KrohnkiteFocusPrev" = "Meta+,";
          "KrohnkiteFocusRight" = "Meta+L";
          "KrohnkiteFocusUp" = "Meta+K";
          "KrohnkiteGrowHeight" = "Meta+Ctrl+J";
          "KrohnkiteIncrease" = "Meta+I";
          "KrohnkiteMonocleLayout" = "Meta+F";
          "KrohnkiteNextLayout" = "Meta+N";
          "KrohnkitePreviousLayout" = "Meta+Shift+N";
          "KrohnkiteRotate" = "Meta+R";
          "KrohnkiteRotatePart" = "Meta+Shift+R";
          "KrohnkiteSetMaster" = "Meta+Return";
          "KrohnkiteShiftDown" = "Meta+Shift+J";
          "KrohnkiteShiftLeft" = "Meta+Shift+H";
          "KrohnkiteShiftRight" = "Meta+Shift+L";
          "KrohnkiteShiftUp" = "Meta+Shift+K";
          "KrohnkiteShrinkHeight" = "Meta+Ctrl+K";
          "KrohnkiteShrinkWidth" = "Meta+Ctrl+H";
          "KrohnkiteStairLayout" = "Meta+T";
          "KrohnkiteToggleFloat" = "Meta+Shift+P";
          "KrohnkitegrowWidth" = "Meta+Ctrl+L";
        };

        # Meta+Q was already KDE's own stock default for this
        # (plasmashell's "manage activities" / Activity Switcher, not
        # something configured deliberately in this config) -- cleared
        # so it doesn't fight with Close Window above for the same key.
        #
        # Everything else in this block (and the ksmserver/powerdevil
        # blocks below) came from a friend's exported KDE shortcut
        # scheme, ~/Desktop/keiboardshortcuts.kksrc.
        shortcuts.plasmashell = {
          "manage activities" = "none";
          "activate application launcher" = "Meta+D";

          # Stock defaults, colliding with kwin's "Switch to Desktop N"
          # (Meta+1..9) above -- nobody deliberately bound these, kept
          # desktop-switching instead.
          "activate task manager entry 1" = "none";
          "activate task manager entry 2" = "none";
          "activate task manager entry 3" = "none";
          "activate task manager entry 4" = "none";
          "activate task manager entry 5" = "none";
          "activate task manager entry 6" = "none";
          "activate task manager entry 7" = "none";
          "activate task manager entry 8" = "none";
          "activate task manager entry 9" = "none";
          "clipboard_action" = "Meta+Ctrl+X";
          "cycle-panels" = [
            "Meta+Ctrl+P"
            "Meta+Alt+P"
          ];
          "next activity" = "Meta+Ctrl+Tab";
          "repeat_action" = "Meta+Ctrl+R";
          "show dashboard" = "Ctrl+F12";
          "show-on-mouse-pos" = "Meta+V";
          "stop current activity" = "Meta+S";
        };

        shortcuts.ksmserver = {
          "Lock Session" = [
            "Screensaver"
            "Meta+Esc"
          ];
          "Log Out" = "Ctrl+Alt+Del";
        };

        shortcuts.org_kde_powerdevil = {
          "Decrease Keyboard Brightness" = "Keyboard Brightness Down";
          "Decrease Screen Brightness" = "Monitor Brightness Down";
          "Decrease Screen Brightness Small" = "Shift+Monitor Brightness Down";
          "Hibernate" = "Hibernate";
          "Increase Keyboard Brightness" = "Keyboard Brightness Up";
          "Increase Screen Brightness" = "Monitor Brightness Up";
          "Increase Screen Brightness Small" = "Shift+Monitor Brightness Up";
          "PowerDown" = "Power Down";
          "PowerOff" = "Power Off";
          "Sleep" = "Sleep";
          "Toggle Keyboard Backlight" = "Keyboard Light On/Off";
          "powerProfile" = [
            "Meta+B"
            "Battery"
          ];
        };

        # Krohnkite dynamic-tiling KWin script -- "krohnkiteEnabled" is
        # its KPlugin.Id (res/metadata.json) with "Enabled" appended,
        # same convention plasma-manager itself uses for Polonium
        # (Plugins.poloniumEnabled in kwin.nix). No typed plasma-manager
        # option exists for Krohnkite specifically, hence the raw
        # configFile escape hatch.
        configFile."kwinrc"."Plugins"."krohnkiteEnabled" = true;

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

      # Krohnkite (dynamic tiling KWin script, enabled via the kwinrc
      # Plugins entry above). Installed per-user rather than system-wide
      # since KWin runs in this user's own session and already picks up
      # share/kwin/scripts from the user's home-manager profile.
      home.packages = [ pkgs.kdePackages.krohnkite ];

      # google-chrome's actual Wayland/scroll-smoothing flags live on the
      # package itself now (modules/users.nix, commandLineArgs override)
      # -- this xdg.configFile approach was removed after confirming
      # nixpkgs' generated launcher wrapper never reads
      # ~/.config/google-chrome-flags.conf at all (that's a Debian/
      # Ubuntu-specific launcher convention, not something this wrapper
      # implements); it was silently doing nothing.

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
      # authored. So this patches only the five GestureButton binding
      # lines in place, byte-identical elsewhere.
      #
      # This activation script previously assumed one flat
      # `[...bindings.GestureButton]` section with five inline-table
      # entries (deliberately, to dodge a TOML round-trip that would
      # reformat it into split [section] headers instead — see prior
      # git history). That assumption broke anyway: OpenLogi's own
      # daemon rewrites this file in exactly that split-section shape
      # whenever it touches it, independent of anything this script
      # does. The grep for the old flat header then matched nothing,
      # and since this runs under home-manager's `set -e` activation
      # script, that silently killed the *entire* activation with no
      # error output — confirmed live via `journalctl -u
      # home-manager-keimoger.service`, failing on every single run
      # since 2026-09-12 right after "Activating
      # openlogiGestureBindings", with nothing after it. Rewritten to
      # target the actual current shape (one `[...GestureButton.<Dir>]`
      # section per direction, confirmed directly against the live
      # file) instead, using python3 for the per-section text
      # replacement rather than nested sed address/change commands --
      # far fewer quoting layers to get wrong for the same result. Not
      # wrapped in `set -e`-defeating error handling, since a missing
      # match now should be a loud failure again: it means the format
      # shifted a third time and this needs another look, not a silent
      # no-op.
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
                  ${pkgs.python3}/bin/python3 - "$configFile" <<'PYEOF'
        import re
        import sys

        path = sys.argv[1]
        with open(path) as f:
            text = f.read()

        device = 'direct:046d:b042:serial:2543apyjhv18'
        shortcuts = {
            "Up": "Switch One Desktop Down",
            "Down": "Switch One Desktop Up",
            "Left": "Switch One Desktop to the Right",
            "Right": "Switch One Desktop to the Left",
            "Click": "Grid View",
        }

        for direction, shortcut in shortcuts.items():
            header = f'[devices."{device}".bindings.GestureButton.{direction}]'
            line = (
                'RunShellCommand = "/run/current-system/sw/bin/qdbus '
                f"org.kde.kglobalaccel /component/kwin invokeShortcut '{shortcut}'\""
            )
            pattern = re.escape(header) + r"\n[^\n]*\n"
            text, n = re.subn(pattern, header + "\n" + line + "\n", text)
            if n != 1:
                sys.exit(f"openlogiGestureBindings: expected exactly one match for {direction!r}, got {n}")

        with open(path, "w") as f:
            f.write(text)
        PYEOF
                fi
      '';

      # ibus-daemon: modules/locale.nix's `i18n.inputMethod` enables and
      # installs ibus, but its own autostart .desktop file ships
      # `NotShowIn=GNOME;KDE` -- its comment defers to "KDE will launch
      # ibus from kwin if enabled in keyboard -> virtual keyboard", a GUI
      # toggle that isn't tracked anywhere in this config, and was never
      # actually turned on. Without an IME running, nothing intercepts
      # the Ctrl+Shift+U hex-codepoint sequence Plover falls back to for
      # any character outside the active keyboard layout, so the raw hex
      # leaks through as literal keystrokes instead of the real character
      # (see modules/plover.nix). Owning the daemon here means it starts
      # every session regardless of KDE's toggle -- confirmed working via
      # the exact same binary+flags, started by hand, during the session
      # this was diagnosed in.
      systemd.user.services.ibus-daemon = {
        Unit = {
          Description = "IBus input method daemon";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "/run/current-system/sw/bin/ibus-daemon --xim --replace";
          Restart = "on-failure";
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
    };
}
