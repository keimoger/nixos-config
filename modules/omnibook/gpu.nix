# GPU-specific acceleration packages for this laptop's Intel Arc 140V
# (Lunar Lake, Xe2). The generic "enable graphics acceleration" switch
# lives in modules/desktop.nix since any machine wants that; only the
# GPU-model-specific package choices live here.
#
# Arc 140V is already driven by the in-kernel `xe` driver + Mesa —
# nothing to swap there. What nixos-generate-config left out is the
# userspace acceleration stack: iHD is the VA-API backend that actually
# supports Xe2 (the older i965 backend doesn't), vpl-gpu-rt is
# oneVPL/Quick Sync, intel-compute-runtime is OpenCL.
{ pkgs, ... }:
{
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    vpl-gpu-rt
    intel-compute-runtime
  ];

  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # Disables PSR2's "selective fetch" sub-feature (only redraws the
  # changed part of the screen) -- the newest, most complex, most
  # bug-prone piece of Panel Self Refresh, and specifically named in an
  # open upstream xe driver bug report describing a Lunar Lake hard
  # freeze over USB-C DP-altmode (the same connection this laptop's
  # external monitor uses via a dock). Confirmed via `modinfo xe` this
  # sub-feature defaults to on. Plain PSR/PSR2 negotiation stays
  # enabled -- this only drops the one specific sub-feature implicated,
  # not PSR's power savings wholesale.
  boot.kernelParams = [ "xe.enable_psr2_sel_fetch=0" ];
}
