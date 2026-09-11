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
}
