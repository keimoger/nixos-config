{ pkgs, ... }:
{
  services.fprintd.enable = true;
  # Override libfprint with TOD (Touch OEM Driver) support, needed for
  # this laptop's fingerprint sensor.
  services.fprintd.package = pkgs.fprintd-tod;

  security.pam.services.sudo.fprintAuth = true;
  security.pam.services.sddm.fprintAuth = true;
  # security.pam.services.kde.fprintAuth = true;
}
