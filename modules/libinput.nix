# Adds touchpad support to libinput's screen-orientation rotation config
# (libinput_device_config_rotation_*), which upstream only wires up for
# generic relative pointers (evdev-fallback.c: mice, trackballs) — the
# touchpad dispatch (evdev-mt-touchpad.c) never calls into that path, so
# the API always reported unavailable for touchpads. See
# modules/patches/libinput-touchpad-rotation.patch for the verified
# patch (applies cleanly, compiles, and confirmed live on this exact
# touchpad — SYNA3580:00 06CB:CFD2 — that `libinput list-devices` now
# reports a real Rotation value instead of n/a).
#
# v2: rotation is applied once, inside tp_get_touches_delta() — the one
# root function pointer motion, two-finger scroll, and swipe/pinch
# gestures all bottom out in (confirmed by tracing every caller) —
# rather than the original v1 approach of patching the pointer-motion
# consumer alone, which left scroll and multitouch gestures unrotated.
# Single point of truth beats patching every consumer site individually.
#
# Internal-struct-only change (tp_dispatch, private to the touchpad
# dispatch files), so it's ABI-compatible: no public function signature
# changes, no new symbols. Nix still rebuilds any direct libinput
# consumer from source when this overlay changes it though, regardless
# of actual ABI compatibility — that's just how content-addressed
# derivations work, not something this patch could avoid.
{ pkgs, ... }:
{
  nix.settings.max-jobs = 1;
  nixpkgs.overlays = [
    (final: prev: {
      libinput = prev.libinput.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/libinput-touchpad-rotation.patch ];
      });
    })
  ];
  environment.systemPackages = [ pkgs.libinput ];

  # Auto-rotate the touchpad with the screen, using the rotation
  # capability the patch above unlocked. KWin already exposes it live
  # per-device over D-Bus (org.kde.KWin /org/kde/KWin/InputDevice/<sys
  # name> — org.kde.KWin.InputDevice, property "rotation", uint32
  # degrees clockwise) via backends/libinput/device.cpp's existing
  # setRotation(), which just calls libinput_device_config_rotation_
  # set_angle() — no KWin patch needed, it already did the right thing
  # for any device where libinput reports the capability available.
  #
  # Looks the touchpad up by its name property rather than a hardcoded
  # /event17 path, since that kernel-assigned number isn't guaranteed
  # stable across reboots/device reordering.
  #
  # Orientation comes from iio-sensor-proxy (net.hadess.SensorProxy,
  # system bus) — polled rather than signal-subscribed, since both
  # `busctl monitor` and `dbus-monitor`'s default path require the
  # privileged org.freedesktop.DBus.Monitoring.BecomeMonitor capability
  # (root-only) on the system bus; a plain Get call needs no special
  # rights. 1s poll interval, imperceptible for something as
  # infrequent as physically rotating a screen.
  #
  # Calibration: normal->0 and bottom-up->180 confirmed correct by
  # physically rotating and testing touchpad feel. right-up->90 and
  # left-up->270 are the standard-convention guess, NOT independently
  # confirmed (the one live test of right-up was inconclusive due to
  # sensor lag, not necessarily wrong math) — first time either comes
  # up naturally, check it and swap the pair below if backwards.
  systemd.user.services.touchpad-autorotate = {
    description = "Rotate the touchpad to match screen orientation";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "touchpad-autorotate" ''
        find_touchpad_path() {
          for p in $(${pkgs.systemd}/bin/busctl --user tree org.kde.KWin 2>/dev/null | grep -oE '/org/kde/KWin/InputDevice/event[0-9]+'); do
            name=$(${pkgs.systemd}/bin/busctl --user get-property org.kde.KWin "$p" org.kde.KWin.InputDevice name 2>/dev/null)
            case "$name" in
              *"SYNA3580:00 06CB:CFD2 Touchpad"*) echo "$p"; return 0 ;;
            esac
          done
          return 1
        }

        device_path=""
        while [ -z "$device_path" ]; do
          device_path=$(find_touchpad_path)
          [ -z "$device_path" ] && ${pkgs.coreutils}/bin/sleep 2
        done

        ${pkgs.systemd}/bin/busctl --system call net.hadess.SensorProxy /net/hadess/SensorProxy net.hadess.SensorProxy ClaimAccelerometer >/dev/null 2>&1 || true

        prev=""
        while true; do
          cur=$(${pkgs.systemd}/bin/busctl --system get-property net.hadess.SensorProxy /net/hadess/SensorProxy net.hadess.SensorProxy AccelerometerOrientation 2>/dev/null | ${pkgs.coreutils}/bin/cut -d'"' -f2)
          if [ -n "$cur" ] && [ "$cur" != "$prev" ]; then
            angle=""
            case "$cur" in
              normal)    angle=0 ;;
              right-up)  angle=270 ;;
              bottom-up) angle=180 ;;
              left-up)   angle=90 ;;
            esac
            if [ -n "$angle" ]; then
              ${pkgs.systemd}/bin/busctl --user set-property org.kde.KWin "$device_path" org.kde.KWin.InputDevice rotation u "$angle"
            fi
            prev="$cur"
          fi
          ${pkgs.coreutils}/bin/sleep 1
        done
      '';
      Restart = "always";
    };
  };
}
