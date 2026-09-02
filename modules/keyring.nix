# Formerly gnome.nix. GNOME itself (mutter/gnome-shell/gnome-session/
# gnome-control-center/gnome-browser-connector) is gone entirely —
# GDM required them unconditionally for its own greeter regardless of
# desktopManager.gnome, so removing them meant dropping GDM back to
# SDDM too (modules/desktop.nix). What's left here is just the
# DE-agnostic infra: gnome-keyring is the actual live secret-service
# backend in use (confirmed via org.freedesktop.secrets D-Bus
# ownership — it already wins over KWallet's ksecretd), and dconf is
# needed by GTK apps generally (Plover included), not gnome-shell
# specifically.
{ pkgs, lib, ... }:
{
  services.gnome.gnome-keyring.enable = true;

  # Needed for GTK apps generally to store/read settings — not
  # gnome-shell-specific, several non-GNOME apps rely on it too.
  programs.dconf.enable = true;

  # Explicit pick regardless of whichever DE-default would otherwise
  # apply — avoids relying on Plasma's own default silently changing
  # under us.
  programs.ssh.askPassword = lib.mkForce "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
}
