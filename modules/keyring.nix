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
  services.gnome.gnome-keyring.enable = false;

  # Needed for GTK apps generally to store/read settings — not
  # gnome-shell-specific, several non-GNOME apps rely on it too.
  programs.dconf.enable = true;

  # GUI for managing the GNOME Keyring "login" collection (change its
  # password, inspect stored secrets) — nothing else on this Plasma
  # system pulls it in, and there's no CLI for changing a keyring's
  # own password (secret-tool only stores/reads individual secrets).
  # Needed to set the login keyring to a blank password so it opens
  # unconditionally — see modules/omnibook/biometrics.nix: fprintd and
  # howdy are "sufficient" on the "login" PAM service, so a successful
  # fingerprint/face match skips pam_unix entirely and the plaintext
  # password pam_gnome_keyring/pam_kwallet5 need to auto-unlock never
  # gets captured. PAM auto-unlock is already correctly wired (see that
  # file's kwallet/enableGnomeKeyring settings, both inherited for free
  # from plasma6.enable and gnome-keyring.enable respectively) but only
  # ever fires on the rare login where the password is typed by hand.
  environment.systemPackages = [ pkgs.seahorse ];

  # Explicit pick regardless of whichever DE-default would otherwise
  # apply — avoids relying on Plasma's own default silently changing
  # under us.
  programs.ssh.askPassword = lib.mkForce "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
}
