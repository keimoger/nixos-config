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
#
# v3: right-edge scroll rotates with the screen too now. Edge-scroll
# zones (evdev-mt-touchpad-edge-scroll.c) are defined in raw physical
# coordinates and don't go through tp_get_touches_delta() at all --
# an entirely separate code path from the motion rotation above, so
# "right-edge scroll" stayed pinned to the physical right edge
# regardless of screen orientation until this. tp_touch_get_edge()
# now remaps which physical edge plays the "logical right"/"logical
# bottom" role based on tp->rotation.angle, derived by solving for
# which physical direction the *inverse* of the existing rotation
# matrix maps to logical right/bottom -- i.e. the same rotation
# convention the motion path already uses, kept consistent rather
# than reasoned about independently. The small-touchpad "no
# horizontal scroll zone" gate (upstream: bottom_edge=INT_MAX at init)
# had to move from a baked-in sentinel to an explicit check at point
# of use, since which physical edge needs gating now depends on the
# current angle rather than being fixed.
{ pkgs, ... }:
let
  # Manual, on-demand haptic buzz -- independent of any actual click.
  # Reverse-engineered from HP's own Windows driver (SynDeviceBridge_
  # inhouse.dll / SynTPEnhService.exe, decompiled with Ghidra): the
  # exported SDB_HapticControl(intensity, 1) triggers a pulse at
  # `intensity` on Report 45 (0x2D) of this exact touchpad, not the
  # passive Report 55 (0x37) Intensity-only control used for click
  # feedback above -- setting Report 55 alone never produced a felt
  # pulse (confirmed live), because it just scales the firmware's own
  # autonomous click-force pulse rather than triggering one.
  #
  # Buffer layout (confirmed live, all four values felt distinctly):
  # [0x2D, 0xFE, 0x01, intensity, 0x01, 0x01]. The 0xFE/0x01 pair and
  # trailing 0x01 aren't arbitrary -- they're copied verbatim from a
  # 5-byte scratch buffer the driver builds internally before relaying
  # it into the real HidD_SetFeature buffer; dropping them (an early,
  # wrong guess) silently no-op'd instead of erroring. Only 25/50/75/
  # 100 are used anywhere in the driver's own call sites, so that's
  # all this exposes -- untested whether other values work, and no
  # reason to guess further given real ones are already known-good.
  touchpadBuzz = pkgs.writeShellScriptBin "touchpad-buzz" ''
    set -e
    intensity="''${1:-100}"
    case "$intensity" in
      25) hex=19 ;;
      50) hex=32 ;;
      75) hex=4b ;;
      100) hex=64 ;;
      *)
        echo "usage: touchpad-buzz [25|50|75|100]" >&2
        exit 1
        ;;
    esac
    exec ${pkgs.hidapitester}/bin/hidapitester --vidpid 06CB:CFD2 -l 6 --open \
      --send-feature "0x2d,0xfe,0x01,0x$hex,0x01,0x01" -q
  '';
in
{
  nix.settings.max-jobs = 1;
  nixpkgs.overlays = [
    (final: prev: {
      libinput = prev.libinput.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/libinput-touchpad-rotation.patch ];
      });
    })
  ];
  environment.systemPackages = [
    pkgs.libinput
    pkgs.hidapitester
    touchpadBuzz
  ];

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

  # Haptic click-force intensity for the same touchpad. Its HID report
  # descriptor exposes a standard HID Haptics usage page (0x0e) "Simple
  # Haptic Controller" with a single "Intensity" Feature report (Report
  # ID 55/0x37, 1 byte, 0-100) -- confirmed via `hid-decode` on
  # /sys/bus/hid/devices/0018:06CB:CFD2.0008/report_descriptor. No
  # Waveform/Trigger/Duration usages are present alongside it, so this
  # is scoped to scaling the force of the existing click-detection
  # pulse, not a freely-triggerable vibration motor -- confirmed live,
  # setting it to 0 didn't stop clicks from registering, just silenced
  # the haptic feedback that normally accompanies one.
  #
  # Linux's in-kernel hid-haptic framework (CONFIG_HID_HAPTIC=y on this
  # kernel) doesn't register an evdev/FF device for this touchpad
  # despite the descriptor being present -- exactly why is unconfirmed,
  # but the Feature report is directly settable over hidraw regardless,
  # via the standard HIDIOCSFEATURE ioctl (this is what hidapitester
  # wraps below). Confirmed live: 0 = no click feedback, 100 = max.
  #
  # The release-click pulse is weaker than the press-click pulse by
  # hardware/firmware design -- at 15 the press was still felt but
  # release silently dropped below its perceptible threshold (looked
  # like a regression at first, wasn't one; confirmed by temporarily
  # raising back to 100, which restored release feedback, then
  # settling on 25 as the floor -- matches the minimum HP's own
  # Windows driver allows, so presumably it's the vendor's own tested
  # floor for keeping both press and release perceptible).
  #
  # A udev rule (rather than a systemd boot-target service, like
  # touchpad-autorotate above) because this is an I2C-HID device that
  # can rebind independent of the display/graphical session -- e.g.
  # after suspend/resume -- and udev fires on every such (re)bind, not
  # just once at boot.
  services.udev.extraRules = ''
    SUBSYSTEM=="hidraw", ENV{HID_ID}=="0018:000006CB:0000CFD2", RUN+="${pkgs.hidapitester}/bin/hidapitester --vidpid 06CB:CFD2 -l 2 --open --send-feature 0x37,25"
  '';
}
