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
# Internal-struct-only change (tp_dispatch, private to the touchpad
# dispatch files), so it's ABI-compatible: no public function signature
# changes, no new symbols. Nix still rebuilds any direct libinput
# consumer from source when this overlay changes it though, regardless
# of actual ABI compatibility — that's just how content-addressed
# derivations work, not something this patch could avoid.
{ ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      libinput = prev.libinput.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/libinput-touchpad-rotation.patch ];
      });
    })
  ];
}
