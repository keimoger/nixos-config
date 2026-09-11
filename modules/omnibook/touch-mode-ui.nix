# Restores/extends tablet-mode-reactive UI scaling that used to be stock
# Plasma behavior, then got mostly reverted upstream after causing
# unrelated layout bugs (KDE Plasma Workspace MR !1394 for systray, MR
# !880 in plasma-desktop for taskmanager). All three patches below use
# the same underlying mechanism: Kirigami.Settings.tabletMode is a
# live, NOTIFY-backed QML property that already correctly mirrors
# org.kde.KWin's TabletModeManager (confirmed live on this hardware) --
# referencing it directly in a property binding gets instant, native
# reactivity with zero external polling/scripting, unlike the systemd-
# service-polling-qdbus approach tried first for the systray piece (see
# git history of this file).
#
#   plasma-systray-tabletmode.patch (plasma-workspace) -- restores the
#     literal reverted binding in applets/systemtray/qml/main.qml:
#     cellSpacing scales via the tabletMode ternary exactly as upstream
#     had it (confirmed via MR !1394's own diff). autoSize is OR'd with
#     tabletMode rather than the config value being overwritten --
#     never found evidence scaleIconsToFit itself was ever a live
#     binding upstream (only a config-write-once-on-entry), so this is
#     a cleaner analog of that half rather than a literal restoration.
#
#   plasma-desktop-taskmanager-tabletmode.patch (plasma-desktop) --
#     restores the literal reverted ternary in applets/taskmanager/qml/
#     code/LayoutMetrics.js (renamed from layout.js upstream since the
#     original MR !880), same tabletMode ? 3 : ... value as upstream.
#
#   aurorae-plastik-tabletmode.patch (aurorae) -- NOT a restoration,
#     since Plastik never had this: titlebar scaling turned out to be a
#     native Breeze C++ feature (see below), never applicable to an
#     Aurorae/QML theme in the first place. This ports the same *idea*
#     (double the base size in tablet mode) into Plastik's own QML
#     instead: titleRow's captionHeight (already aliased to buttonSize,
#     so this scales button size and title height together) doubles
#     when Kirigami.Settings.tabletMode is true, and a Connections block
#     re-issues Plastik's own borders.setTitle()/maximizedBorders.
#     setTitle() calls (which only ever ran once at Component.
#     onCompleted, not a reactive binding), mirroring its existing
#     Connections block for decorationSettings' borderSizeChanged.
#     Built and confirmed applying cleanly, but NOT yet actually
#     verified live -- discovered mid-testing that this laptop's active
#     decoration theme is a third theme entirely (`windows98-aurorae`,
#     an SVG-based Aurorae theme, set at some point after this was
#     written), so this patch was never actually being exercised. Kept
#     in case Plastik gets switched back to.
#
#   breeze-decoration-tabletmode.patch (breeze, kdecoration/) --
#     restores the *actual* original titlebar/button-size mechanism:
#     native Breeze C++ (breezedecoration.cpp), not QML. Ported from
#     KDE commit 13e74d87b91bea09e423220f1d231f12ec1bb98a (~Plasma
#     5.24-5.25, bug 418904, "Use KWin's tablet mode to increase
#     decoration button size using touch"), fully absent from current
#     breeze-6.7.4 source (confirmed via full-source grep) -- ported by
#     hand since the underlying code has moved on since 2022
#     (buttonHeight() -> buttonSize(), etc; verified against the actual
#     current source tree, not the stale historical diff context).
#     Subscribes directly to org.kde.KWin's TabletModeManager D-Bus
#     tabletModeChanged signal (same interface polled/used elsewhere in
#     this file's siblings), doubles buttonSize()'s base gridUnit in
#     tablet mode, and calls recalculateBorders()+updateButtonsGeometry()
#     -- captionHeight() and the border-top calculation already derive
#     from buttonSize(), so titlebar height follows with no separate
#     change needed. Only applies to native Breeze -- switch the active
#     decoration (org.kde.kdecoration2 / library=org.kde.breeze in
#     kwinrc, no theme= key) to actually exercise this.
#
#   breeze-kstyle-tabletmode.patch (breeze, kstyle/) -- restores the
#     *other* half the user remembered but couldn't name: Breeze's
#     QWidget *style* (separate from the decoration above) enlarging
#     line edits, combo boxes, buttons, checkboxes, menus, sliders, and
#     tab bars in QWidget-based apps during tablet mode. Ported from two
#     historical commits: fb7071a1cf78 (added Style::isTabletMode(),
#     originally a thin wrapper around Kirigami::TabletModeWatcher) and
#     3fe906b0bc687b57961f61e9a7a6a00f270fd9ce (added the
#     formFactorMetric() dispatcher, the 12 *_Tablet metric constants in
#     breezemetrics.h, and routed all ~60 call sites through it).
#     Deliberately deviates from the historical implementation for
#     isTabletMode() itself: rather than adding a new Kirigami C++
#     library dependency to kstyle (which would need new CMakeLists.txt
#     linking against an unverified KF6 CMake target name -- real risk
#     for a first-attempt patch), it's implemented via the same direct
#     org.kde.KWin TabletModeManager D-Bus subscription as the
#     decoration patch above, sharing no code with it (separate
#     compiled Qt plugin) but using the identical, already-proven
#     mechanism. Fully absent from current source (confirmed via
#     full-source grep) -- also fully absent was a `constexpr` use of
#     Slider_ControlThickness at one call site that can't call a
#     runtime function; changed to a plain `const` local there instead,
#     the only call site needing more than a straight token swap.
#     MenuItem_MarginHeight's base value has drifted since 2022 (3 -> 4
#     in current source) -- its _Tablet variant was scaled to the same
#     ~2x ratio (8) rather than reusing the stale historical absolute
#     number (6), to stay faithful to intent over letter.
{ pkgs, ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      kdePackages = prev.kdePackages // {
        plasma-workspace = prev.kdePackages.plasma-workspace.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ./patches/plasma-systray-tabletmode.patch ];
        });
        plasma-desktop = prev.kdePackages.plasma-desktop.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ./patches/plasma-desktop-taskmanager-tabletmode.patch ];
        });
        aurorae = prev.kdePackages.aurorae.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ./patches/aurorae-plastik-tabletmode.patch ];
        });
        breeze = prev.kdePackages.breeze.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ./patches/breeze-decoration-tabletmode.patch
            ./patches/breeze-kstyle-tabletmode.patch
          ];
        });
      };
    })
  ];
}
