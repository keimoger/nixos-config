{ lib, ... }:
{
  # Local Windows guests for applications that do not run reliably under
  # Wine. KVM provides hardware acceleration; virt-manager is the GUI.
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  users.users.keimoger.extraGroups = lib.mkAfter [
    "libvirtd"
    "kvm"
  ];
}
