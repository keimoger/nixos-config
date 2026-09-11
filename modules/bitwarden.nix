# Bitwarden Desktop itself is installed per-user (modules/users.nix,
# users.users.keimoger.packages), not via environment.systemPackages --
# which means its own bundled polkit action file
# (${bitwarden-desktop}/share/polkit-1/actions/com.bitwarden.Bitwarden.
# policy) never lands in /run/current-system/sw/share/polkit-1/actions,
# the one directory polkit on this system actually scans (confirmed
# live: that's where howdy's own *.policy file already lives; a bare
# /etc/polkit-1/actions doesn't even exist here). Without that action
# registered, polkit has nothing to authorize the biometric-unlock
# request against, so the desktop app's "Unlock with system
# authentication" flow can't complete -- this is a known, filed
# nixpkgs issue (NixOS/nixpkgs#344073), not something misconfigured on
# this machine specifically. The browser (Chrome) side of this was
# already fine on its own -- its native-messaging-hosts manifest
# already pointed at a real, working proxy binary, not the broken
# Electron-path bug that same issue describes for Firefox.
#
# Rather than also adding the full bitwarden-desktop package to
# environment.systemPackages (which would just duplicate the per-user
# install for the sake of one file), this pulls out only the one
# actually-needed file into its own tiny package.
{ pkgs, ... }:
{
  environment.systemPackages = [
    (pkgs.runCommand "bitwarden-polkit-policy" { } ''
      mkdir -p $out/share/polkit-1/actions
      cp ${pkgs.bitwarden-desktop}/share/polkit-1/actions/com.bitwarden.Bitwarden.policy \
        $out/share/polkit-1/actions/
    '')
  ];
}
