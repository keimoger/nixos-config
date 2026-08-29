# vboard: alternative on-screen keyboard with modifier key support
# (Ctrl/Alt/Super), unlike Plasma's built-in one. Not in nixpkgs yet,
# so built from source here.
#   https://github.com/archisman-panigrahi/vboard
#
# NOTE: this derivation is untested — I don't have a NixOS sandbox to
# build it in. Treat it as a solid starting point, not a guaranteed
# drop-in.
#
# After installing, run this ONCE as your normal user (not root) to
# register vboard's KWin window rule (skip-taskbar, keep-above, etc.)
# — this writes to your own ~/.config, which the Nix build sandbox
# can't and shouldn't touch:
#
#   bash /run/current-system/sw/share/vboard/scripts/install-kwin-rule.sh
#
# (or find the exact store path with:
#   find /nix/store -maxdepth 1 -iname 'vboard-*' 2>/dev/null
# and run the script from .../share/vboard/scripts/ inside it)
#
# vboard's own uinput setup script is skipped entirely — you already
# have equivalent permissions via modules/users.nix
# (hardware.uinput.enable + the "uinput" group + udev rule).
{ pkgs, lib, ... }:
let
  vboardPython = pkgs.python3.withPackages (ps: [
    ps.pygobject3
    ps.python-uinput
    ps.pycairo
  ]);

  vboard = pkgs.stdenv.mkDerivation rec {
    pname = "vboard";
    version = "unstable-2026-08-27";

    src = pkgs.fetchFromGitHub {
      owner = "archisman-panigrahi";
      repo = "vboard";
      rev = "main"; # consider pinning to a specific commit/tag instead
      hash = "sha256-Pl3xLzaFscLX7myOqE/hIvfYwIy5NbfxN2Ur4K1f3nc=";
    };

    nativeBuildInputs = with pkgs; [
      meson
      ninja
      pkg-config
      wrapGAppsHook3
      gobject-introspection
    ];

    buildInputs = with pkgs; [
      gtk3
      libayatana-appindicator
      vboardPython
    ];

    # meson.build runs scripts/meson-post-install.sh as a post-install
    # step, which tries to register a KWin window rule and touch
    # desktop/icon-cache state for a *live user session*. None of that
    # makes sense inside the sandboxed Nix build (no $HOME, no real
    # desktop, minimal PATH). Neutralize it here — but keep a valid
    # shebang and the executable bit, or meson can't even exec the
    # file at all ("could not be run", i.e. exit 127).
    postPatch = ''
      cat > scripts/meson-post-install.sh <<'EOF'
      #!/bin/sh
      exit 0
      EOF
      chmod +x scripts/meson-post-install.sh
    '';

    postFixup = ''
      wrapProgram $out/bin/vboard \
        --prefix PYTHONPATH : "${vboardPython}/${vboardPython.sitePackages}" \
        --prefix GI_TYPELIB_PATH : "${pkgs.gtk3}/lib/girepository-1.0:${pkgs.libayatana-appindicator}/lib/girepository-1.0"
    '';

    meta = with lib; {
      description = "Wayland-compatible on-screen keyboard with modifier key support for KDE Plasma";
      homepage = "https://github.com/archisman-panigrahi/vboard";
      license = licenses.gpl3Only;
      platforms = platforms.linux;
      mainProgram = "vboard";
    };
  };
in
{
  environment.systemPackages = [ vboard ];
}
