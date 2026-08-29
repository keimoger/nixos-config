# GNOME, enabled alongside Plasma so it shows up as a second session
# option at the SDDM login screen. Nothing hardware-level (sensors,
# ISH firmware, kernel modules) is DE-specific — all of that carries
# over regardless of which session you pick.
#
# Once you've tried it and decided, you can either:
#   - keep both installed and just pick per-login, or
#   - delete modules/desktop.nix's Plasma bits and this comment once
#     you're sure, to stop building both desktops on every rebuild.
#
# NOTE: untested — I don't have a sandbox to verify SDDM + GNOME works
# perfectly together on the first try. The combination is common and
# well-trodden, but keyring/portal integration occasionally needs a
# nudge on non-GDM login managers. If gnome-keyring doesn't unlock
# automatically at login, that's the first thing to check.
{ pkgs, lib, ... }:
{
  services.desktopManager.gnome.enable = true;
  services.gnome.gnome-keyring.enable = true;

  # Both Plasma and GNOME set their own default SSH "ask password"
  # helper (ksshaskpass vs seahorse's ssh-askpass) at the same
  # priority, which NixOS refuses to silently resolve. Pick one
  # explicitly — it works fine from either session regardless of which
  # DE you're actually logged into.
  programs.ssh.askPassword = lib.mkForce "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
}
