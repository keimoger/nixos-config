# The upstream test launcher patches app.asar and runs a localhost proxy.
# Patch at build time: installed applications in /nix/store are read-only.
{ pkgs }:
let
  base = pkgs.lycheeslicer;
  launcher = pkgs.buildGoModule {
    pname = "lychee-slicer-launcher";
    version = "1.1";
    src = pkgs.fetchzip {
      url = "https://vaclive.party/software/lychee-slicer/archive/v1.1.tar.gz";
      hash = "sha256-UAbr5F3MkalrP9Ms5wPP4LjLWwGWjQZZ0arqTDuCtF0=";
    };
    vendorHash = "sha256-Ix4JGhFXxv1kZNSyTGdRe3RSuCQ3plaFW4a2iLmogGE=";
    subPackages = [ "." ];
    postPatch = ''
      # Creating licenses[0] when the server returns [] produces an invalid
      # license (no type or application), crashing Lychee's account loader.
      substituteInPlace main.go \
        --replace-fail 'b, _ = sjson.Set(b, "data.user.licenses.0.macAddressesLimit", 9999999)' \
          '// Preserve the server license list, including an empty list.' \
        --replace-fail 'log.Println(name+":", b)' 'log.Println("Response:", name)' \
        --replace-fail 'log.Fatal(cmd.Run())' 'if err := cmd.Run(); err != nil { log.Fatal(err) }'
    '';
    postInstall = ''
      mv $out/bin/lychee-slicer $out/bin/lychee-slicer-launcher
    '';
  };
  extracted = pkgs.appimageTools.extract {
    inherit (base) pname version src;
  };
  patched = pkgs.runCommand "lycheeslicer-${base.version}-patched" { } ''
    cp -a ${extracted} $out
    chmod u+w $out/resources/app.asar
    ${launcher}/bin/lychee-slicer-launcher -patch -program $out/lycheeslicer
  '';
  run = pkgs.writeShellScript "lycheeslicer-launch" ''
    export APPDIR=${patched}
    # Forward callbacks to the existing instance and reuse its proxy.
    if ${pkgs.procps}/bin/pgrep -u "$UID" -f ${
      pkgs.lib.escapeShellArg ("^" + pkgs.lib.escapeRegex "${patched}/lycheeslicer" + "( |$)")
    } > /dev/null; then
      exec ${patched}/AppRun "$@"
    fi
    exec ${launcher}/bin/lychee-slicer-launcher -proxy -program ${patched}/AppRun -- "$@"
  '';
  desktop = pkgs.makeDesktopItem {
    # Lychee itself registers this exact desktop ID on startup.
    name = "LycheeSlicer";
    desktopName = "Lychee Slicer (Test Launcher)";
    genericName = "3D Slicer";
    exec = "lycheeslicer %U";
    icon = "lycheeslicer";
    startupWMClass = "LycheeSlicer";
    categories = [ "Graphics" ];
    mimeTypes = [
      "model/stl"
      "x-scheme-handler/lycheeslicer"
    ];
    terminal = false;
  };
in
pkgs.buildFHSEnv (
  pkgs.appimageTools.defaultFhsEnvArgs
  // {
    pname = "lycheeslicer";
    inherit (base) version;
    targetPkgs = p: pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p ++ [ p.libxshmfence ];
    runScript = run;
    extraInstallCommands = ''
      install -Dm444 ${desktop}/share/applications/LycheeSlicer.desktop $out/share/applications/LycheeSlicer.desktop
      substituteInPlace $out/share/applications/LycheeSlicer.desktop \
        --replace-fail 'Exec=lycheeslicer %U' "Exec=$out/bin/lycheeslicer %U"
      install -Dm444 ${extracted}/lycheeslicer.png $out/share/icons/hicolor/512x512/apps/lycheeslicer.png
    '';
    meta = base.meta // {
      description = "Lychee Slicer with the vaclive test launcher";
    };
  }
)
