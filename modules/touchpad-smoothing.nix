# Smooths slow single-finger touchpad cursor movement -- see
# ./touchpad-smoothing.lua for the full explanation and the actual logic.
{ ... }:
{
  environment.etc."libinput/plugins/60-touchpad-smoothing.lua".source = ./touchpad-smoothing.lua;
}
