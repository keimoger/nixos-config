# Everything specific to this exact machine -- an HP OmniBook Ultra
# Flip 14-fh0013dx (Intel Core Ultra 7 256V / Lunar Lake, Intel Arc
# 140V, Synaptics SYNA3580:00 06CB:CFD2 haptic touchpad, Intel ISH
# sensor hub, HP 9MP RGB+IR camera). None of this is portable to other
# hardware -- comment out the single import of this directory in
# ../../configuration.nix to deploy this config elsewhere.
#
#   sensors.nix        -- ISH firmware + kernel modules for the
#                          accelerometer/hinge/orientation sensor stack
#   touchpad.nix        -- from-scratch libinput patch adding rotation
#                          support to this exact touchpad, plus the
#                          screen-follows-sensor autorotate service and
#                          the reverse-engineered haptic click/buzz
#                          control (Report 45 on this exact HID device)
#   rotation-lock.nix   -- tray toggle trading sensor-driven rotation
#                          off in exchange for the EC not disabling the
#                          keyboard when physically rotated on its side
#   gpu.nix             -- Arc 140V (Lunar Lake) VAAPI/QuickSync/OpenCL
#                          package choices
#   biometrics.nix      -- fingerprint (TOD driver for this exact
#                          sensor) + face auth (this exact IR camera's
#                          device path and exposure tuning)
#   copilot-key.nix     -- remaps this laptop's dedicated Copilot key
#                          (a Meta+Shift+F23 hardware chord) to Right
#                          Ctrl. Rewritten from scratch after an
#                          earlier keyd-based version caused a severe
#                          live failure (device wildcard grabbed the
#                          steno keyboard too) -- see the comments in
#                          that file for the full story.
#   touch-mode-ui.nix   -- bigger systray icons + window titlebar size
#                          automatically in tablet mode (this being a
#                          convertible), reverting to plain Plasma
#                          defaults otherwise
{
  imports = [
    ./sensors.nix
    ./touchpad.nix
    ./rotation-lock.nix
    ./gpu.nix
    ./biometrics.nix
    # ./copilot-key.nix
    ./touch-mode-ui.nix
  ];
}
