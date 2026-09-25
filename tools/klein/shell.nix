let
  flake = builtins.getFlake (toString ../..);
  pkgs = flake.nixosConfigurations.keibook.pkgs;
in
pkgs.mkShell {
  packages = [ pkgs.python312 pkgs.uv ];
  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
    pkgs.ocl-icd
    pkgs.level-zero
  ] + ":/run/opengl-driver/lib";
  UV_PYTHON = "${pkgs.python312}/bin/python3";
  UV_PYTHON_DOWNLOADS = "never";
  shellHook = ''
    export UV_PROJECT_ENVIRONMENT="''${XDG_DATA_HOME:-$HOME/.local/share}/klein/venv"
  '';
}
