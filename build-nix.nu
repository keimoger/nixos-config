# Builds and switches this system's NixOS configuration.
#
# "remote" builds the WHOLE system closure on the LAN builder box
# (copies the derivation over, builds there, copies the result back,
# then switches locally) -- the original behavior of this script, when
# it was build-remote.nu.
#
# "local" builds and switches right here instead, piped through `nom`
# (nix-output-monitor) for readable live progress instead of raw nix
# log spam.
#
# "heavy" builds ONLY the genuinely heavy, source-patched packages
# (see $heavy_packages below) on the remote box, copies just those
# results back, then does a normal LOCAL build/switch for everything
# else. Use this instead of "remote" when the remote machine's own
# disk is tight -- pulling in the whole system closure there (every
# small package too, not just the patched ones) wastes remote space it
# doesn't have right now, whereas this only ever asks it to build the
# handful of things that actually take a while to compile from source.
#
# Usage:
#   nu build-nix.nu remote
#   nu build-nix.nu local
#   nu build-nix.nu heavy
#   nu build-nix.nu            # no mode given -- picks interactively

def main [mode?: string] {
    # Always operate from the directory containing this script, so it can be
    # invoked as `nu /home/keimoger/nix-config/build-nix.nu local` from any
    # working directory.  FILE_PWD is set by Nushell for the current script;
    # the fallback keeps `source build-nix.nu` usable from an interactive cwd.
    let config_dir = ($env.FILE_PWD? | default (pwd) | path expand)
    cd $config_dir

    let chosen = if $mode != null {
        $mode
    } else {
        ["local" "remote" "heavy"] | input list "Select build mode:"
    }

    if $chosen == "remote" {
        build-remote
    } else if $chosen == "local" {
        build-local
    } else if $chosen == "heavy" {
        build-heavy
    } else if $chosen == null {
        print "No mode selected."
        exit 1
    } else {
        print $"Unknown mode: \"($chosen)\" -- expected \"remote\", \"local\", or \"heavy\""
        exit 1
    }
}

# Copies a built remote derivation's output(s) back to the local
# store. `outputs` is nix's own output-selector syntax -- "out" for
# just the main runtime output, or "*" for every output the derivation
# has. Defaults to "out" only: for a multi-output package like kwin
# (out/dev/devtools/debug), "dev"/"devtools"/"debug" are only needed by
# something else building *against* it (headers, a debugger) -- not by
# `nixos-rebuild switch`, which only ever needs "out" to deploy and run
# it. Skipping those avoids transferring what's easily the largest
# chunk of the closure (debug symbols routinely run hundreds of MB+)
# for nothing. If a local build ever genuinely complains about a
# missing dev/debug path from one of these packages, that specific
# call site is the place to widen it back to "*".
#
# `nix build --print-out-paths` on a multi-output selection prints one
# path per line -- `| lines` turns that into a proper list, and `...`
# spreads it as separate arguments to `nix copy` instead of one mangled
# multi-line string (which is what silently broke this before: nix
# copy saw a single argument with embedded newlines and tried to treat
# the whole blob as one nonexistent path).
def copy-back-outputs [ssh_host: string, remote_port: int, built_drv: string, outputs: string = "out"] {
    print $"  copying back \(($outputs))..."

    let remote_result = (
        ssh $ssh_host -p $remote_port nix build --print-out-paths --extra-experimental-features '"nix-command flakes"' $"($built_drv)^($outputs)"
        | complete
    )
    if $remote_result.exit_code != 0 {
        print -e $remote_result.stderr
        error make { msg: $"remote output-path lookup failed (exit ($remote_result.exit_code))" }
    }
    let built_paths = ($remote_result.stdout | lines | where {|path| $path != "" })
    if ($built_paths | is-empty) {
        error make { msg: $"remote build returned no paths for ($built_drv)^($outputs)" }
    }

    # --no-check-sigs: paths built on the remote box aren't signed by
    # any key the local daemon already trusts, so it refuses them by
    # default ("lacks a signature by a trusted key"). This flag skips
    # that check -- only actually honored by the daemon because this
    # user is listed in nix.settings.trusted-users (modules/boot.nix);
    # an untrusted user passing this same flag would just have it
    # ignored and hit the same error anyway.
    #
    # nix copy's own live progress bar needs a real TTY to render,
    # which it doesn't reliably get from inside this script -- even
    # with -v it printed nothing at all here. nom (already used for
    # build progress elsewhere in this script) understands the same
    # internal-json activity stream for copy/substitution progress too,
    # not just builds, so route through it the same way instead of
    # nix copy's own (non-rendering, here) display.
    try {
        nix copy --log-format internal-json -v --no-check-sigs --from ssh-ng://($ssh_host):($remote_port) ...$built_paths o+e>| nom --json
    }

    print $"  ($outputs) copied."
}

def build-remote [] {
    let remote_addr = '192.168.8.16'
    let remote_port = 2222
    let ssh_host = $"builder@($remote_addr)"
    let host = (hostname)
    mkdir build-logs
    let build_log = "build-logs/remote-build.log"

    let built_drv = (nix eval $".#nixosConfigurations.($host).config.system.build.toplevel.drvPath" --json | from json)

    nix copy --to ssh-ng://($ssh_host):($remote_port) $built_drv

    # Does the actual remote build, piped through nom for live, readable
    # progress -- internal-json is the log format nom itself parses. Its
    # result path isn't captured here: nom consumes the whole pipeline's
    # output for its own display, so anything piped through it can't
    # also be captured as a value in the same breath. copy-back-outputs
    # re-runs the build against what's now fully cached to grab the
    # path(s) near-instantly instead, with nom out of the way.
    try {
        ssh $ssh_host -p $remote_port nix build --extra-experimental-features '"nix-command flakes"' --log-format internal-json -v $"($built_drv)^*" o+e>| ^tee $build_log | nom --json
    }
    print $"  raw build log saved to ($build_log)"

    # "*" here (not the "out"-only default): this is the whole system
    # closure, which needs everything it actually references to
    # activate -- unlike build-heavy below, there's no single well-
    # known output to prefer.
    copy-back-outputs $ssh_host $remote_port $built_drv "*"

    let local_log = "build-logs/local-after-remote.log"
    try {
        env NIXOS_REBUILD_NO_SYSTEMD_RUN=1 nixos-rebuild switch --flake . --sudo --builders "" o+e>| ^tee $local_log | nom
    }
    print $"  raw local build log saved to ($local_log)"
}

def build-local [] {
    # Override the configured remote builders for this invocation.  Keep the
    # stream live: capturing `nixos-rebuild` with `complete` first buffers all
    # stdout/stderr until the build exits, which makes a long local build look
    # frozen.  Nix's internal-json stream feeds nom incrementally while tee
    # preserves the raw log on disk.
    mkdir build-logs
    let build_log = "build-logs/local-build.log"
    try {
        env NIXOS_REBUILD_NO_SYSTEMD_RUN=1 nixos-rebuild switch --flake . --sudo --builders "" --log-format internal-json -v o+e>| ^tee $build_log | nom --json
    }
    print $"  raw local build log saved to ($build_log)"
}

def build-heavy [] {
    # Flake attribute paths (relative to `pkgs`) for whatever's
    # currently slow enough to be worth sending to the remote box
    # instead of recompiling here -- every package this config patches
    # from source (grepped for `patches = (old.patches or [ ]) ++` across
    # modules/omnibook/touchpad.nix and modules/omnibook/touch-mode-ui.nix
    # to build this list, rather than trusting memory). Add to this list
    # as more packages end up patched and become worth offloading too.
    # Every entry copies "*" because a later system realization may need a
    # dev/debug output while building another package. Copying only "out"
    # can make the final local phase rebuild the entire patched derivation,
    # defeating the remote build.
    let heavy_packages = [
        { pkg: "kdePackages.kwin", outputs: "*" } # touchpad.nix: gesture threshold/distance patches
        { pkg: "libinput", outputs: "*" } # touchpad.nix: touchpad rotation + macos cursor accel patches
        { pkg: "kdePackages.plasma-workspace", outputs: "*" } # touch-mode-ui.nix: systray tabletmode patch -- other local builds need its "dev" output, see comment above
        { pkg: "kdePackages.plasma-desktop", outputs: "*" } # touch-mode-ui.nix: taskmanager tabletmode patch
        { pkg: "kdePackages.kdeplasma-addons", outputs: "*" } # large Plasma addon collection with C++/QML and Rust components
        { pkg: "kdePackages.aurorae", outputs: "*" } # touch-mode-ui.nix: plastik tabletmode patch
        { pkg: "kdePackages.breeze", outputs: "*" } # touch-mode-ui.nix: decoration + kstyle tabletmode patches
    ]

    let remote_addr = '192.168.8.16'
    let remote_port = 2222
    let ssh_host = $"builder@($remote_addr)"
    let host = (hostname)
    mkdir build-logs

    for entry in $heavy_packages {
        let pkg = $entry.pkg
        let build_log = $"build-logs/heavy-($pkg).log"
        print $"=== building ($pkg) remotely ==="

        let built_drv = (nix eval $".#nixosConfigurations.($host).pkgs.($pkg).drvPath" --json | from json)

        nix copy --to ssh-ng://($ssh_host):($remote_port) $built_drv

        # Same nom-for-progress / re-run-for-the-path split as
        # build-remote above -- see its comment for why this is two
        # calls instead of one.
        try {
            ssh $ssh_host -p $remote_port nix build --extra-experimental-features '"nix-command flakes"' --log-format internal-json -v $"($built_drv)^*" o+e>| ^tee $build_log | nom --json
        }

        true
        copy-back-outputs $ssh_host $remote_port $built_drv $entry.outputs
        true
    }

    # Everything in $heavy_packages is now already present in the local
    # store, including all outputs. This final local phase should therefore
    # only realize the remaining light system closure and activate it.
    print "=== remote heavy packages complete; realizing the remaining system locally ==="
    build-local
}
