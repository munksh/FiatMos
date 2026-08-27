pragma Singleton

import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

// Fiat colours — the family standard. Two palettes behind one set of names,
// switched by a single boolean that is remembered between runs.
//
//   ambient = true   the user's ambience via Theme.*. No background is
//                    painted anywhere; the wallpaper is the background.
//   ambient = false  Fiat colours. The app paints its own light background
//                    and uses the family palette.
//
// Semantic colours ignore both. They mean something, so they only shift
// between a dark and a light variant to keep contrast.

QtObject {
    id: t

    // ---- the switch, remembered between runs ----
    property ConfigurationValue ambientConfig: ConfigurationValue {
        key: "/apps/harbour-fiatmos/ambient"
        defaultValue: true
    }
    readonly property bool ambient: ambientConfig.value
    function setAmbient(on) { ambientConfig.value = on }

    // Fiat colours are a light scheme, so dark is false there.
    readonly property bool dark: ambient ? (Theme.colorScheme === Theme.LightOnDark) : false

    readonly property string serif: "Georgia"

    // ---- the notch ----
    //
    // Silica's own PageHeader clears the cutout. Ours do not, because they are
    // ours -- and on the Jolla Phone (2026) that puts the top of a capital
    // letter, and the left end of a long right-aligned title, straight into the
    // hole. So every header in this app starts this far down.
    //
    // Read from the platform when the platform will say. The property is not
    // guaranteed to exist, and asking a QObject for a property it does not have
    // returns undefined rather than throwing, so the probe is safe -- but it
    // does mean the fallback has to be a real number, not a hope.
    function cutoutHeight() {
        if (typeof Screen === "undefined" || Screen === null) return -1
        var c = Screen.topCutout
        if (c === undefined || c === null) return -1
        if (typeof c === "number") return c
        if (c.height !== undefined) return c.height
        return -1
    }

    // Tune this one number if the clearance is wrong on a device that does not
    // report its cutout. It is the only place the value lives.
    //
    // Smaller than it first was: the headers used to centre their title in a
    // tall band, so they needed the inset AND the band. Now the title hangs
    // from the top of the band and the inset is the whole clearance.
    readonly property real headerTopInsetFallback: Theme.paddingLarge * 1.5

    readonly property real headerTopInset: {
        var c = cutoutHeight()
        return c >= 0 ? c + Theme.paddingMedium : headerTopInsetFallback
    }

    // Where the system's own indicators sit -- the little lights along the top
    // of the screen. Anything of ours that belongs on that line (the wordmark,
    // Cancel, Save) is centred on it rather than given a top margin, so it
    // reads as part of the same row instead of nearly part of it.
    //
    // This is simply where they always were, before any of the notch work:
    // the old headers were an Item of itemSizeLarge with the wordmark and the
    // dialog actions on its vertical centre. That position was right, and two
    // attempts at deriving it from the cutout -- itemSizeExtraSmall / 2, then
    // headerTopInset / 2 -- both walked it further up the screen for no
    // reason. The actions never needed the clearance; only the title did.
    //
    // So: back to the known-good number, written down rather than derived.
    // Bigger moves them down, smaller moves them up.
    readonly property real statusRowCenter: Theme.itemSizeLarge / 2

    // ---- text and accent ----
    readonly property color primaryText:   ambient ? Theme.primaryColor   : "#1A1A1A"
    readonly property color secondaryText: ambient ? Theme.secondaryColor : Qt.rgba(0.10, 0.10, 0.10, 0.55)

    // Fiat Mos's accent: moss. Habit and growth — the thing that comes back.
    // It does not collide with this app's semantic colour, which is red;
    // see the note by offTarget below.
    readonly property color accent: ambient ? Theme.highlightColor : "#4E6B3A"

    // ---- the shared paper ----
    readonly property color backgroundHigh: "#F2EFE8"
    readonly property color backgroundLow:  "#D8D2C6"

    readonly property color card: ambient
        ? (dark ? Qt.rgba(0.08, 0.08, 0.08, 1.0) : Qt.rgba(0.96, 0.96, 0.96, 1.0))
        : "#F5F5F5"
    readonly property color surface: card
    readonly property color cardBorder:   Theme.rgba(primaryText, 0.45)
    readonly property color innerBorder:  Theme.rgba(primaryText, 0.22)
    readonly property color recessFill:   Theme.rgba(primaryText, 0.05)
    readonly property color recessBorder: Theme.rgba(primaryText, 0.16)
    readonly property real cardRadius: Theme.paddingLarge * 2
    readonly property int cardBorderWidth: 2

    // ---- pills ----
    readonly property color pillFill:         Theme.rgba(primaryText, 0.15)
    readonly property color pillBorder:       Theme.rgba(primaryText, 0.55)
    readonly property color pillFillActive:   Theme.rgba(accent, 0.15)
    readonly property color pillBorderActive: Theme.rgba(accent, 0.45)

    // ---- meaning, never decoration ----
    //
    // Fiat Mos has one verdict colour: something is wrong. It marks a
    // numeric habit sitting far from its target, and invalid input in a
    // form. There is deliberately no "good" green -- a green would sit on
    // top of the moss accent, and the family rule is that an accent must not
    // collide with a semantic colour. Being logged is a state, not a
    // verdict, so it stays in the accent.
    readonly property color wrong: dark ? "#A0403A" : "#8A2B25"

    // Unfilled dots, ring tracks, empty cells, anything absent.
    readonly property color dotIdle: Theme.rgba(primaryText, 0.22)

    // The mark beside a running streak. Decorative, not semantic -- it says
    // "this one is alive", not "this one is right" -- so it does not belong
    // in the verdict table above. It still lives here rather than inline,
    // because a hardcoded hex in a page is how ambient mode breaks in one
    // corner without anyone noticing.
    readonly property color streakMark: ambient ? Theme.highlightColor : "#B5651D"

    // Readable mark drawn on top of an accent fill.
    //
    // This used to be `card`, which guessed from the colour SCHEME. That is
    // the wrong question -- what matters is how light the accent actually is,
    // and an ambience can pair a light scheme with a dark highlight or the
    // other way round. So measure it: perceived luminance of the accent
    // decides whether the mark on top is dark or light. Right in every
    // ambience, and right under Fiat colours, without a special case.
    // A function, not a chain of readonly bindings. The chained version came
    // out undefined on the device -- and an undefined colour does not shout,
    // it silently renders black. Evaluated at the call site there is nothing
    // to resolve in the wrong order.
    function markOn(c) {
        if (c === undefined || c === null) return "#F5F5F5"
        return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) > 0.55 ? "#1A1A1A" : "#F5F5F5"
    }

    readonly property color onAccent: markOn(accent)

    // ---- the maker's mark ----
    //
    // Taupe, and a FIXED value: this one deliberately does not follow the
    // ambience, for the same reason the launcher icon does not. It is
    // Munkstolen's colour, not the app's, and a signature that changed colour
    // with the wallpaper would not be a signature.
    //
    // Chosen to survive both grounds rather than to look best on one. Against
    // the Fiat cream it measures 3.96:1, against a black ambience 4.36:1, and
    // against a dark grey one 3.67:1 -- all above the 3:1 that graphical
    // objects and large text need. A darker taupe reads better on paper and
    // disappears on black; a lighter one does the reverse. This is the middle.
    readonly property color makerMark: "#7E7566"

    // The wash under a pressed row or menu item. Silica would use the
    // ambience highlight here, which bleeds through Fiat colours; this keeps
    // the press in the app's own accent.
    readonly property color highlightWash: Theme.rgba(accent, 0.15)

    // ---- Silica's own chrome ----
    //
    // Menus, pull-down drawers, ComboBox values, TextField labels and
    // underlines, sliders, selection: none of these takes a colour from us.
    // They read Theme.* directly, which is the ambience, which is why they
    // stayed ambience-coloured under Fiat colours no matter how many
    // `color:` lines we added to individual items.
    //
    // Silica's answer to this is `palette` -- a set of colour roles that
    // hangs off an item and is INHERITED by its children. Set it once on the
    // ApplicationWindow and every Silica control below it follows.
    //
    // Written defensively on purpose. `palette` and its roles are not
    // guaranteed to exist on every Silica version, and a missing property
    // assigned in a QML binding is a load-time error -- the whole page dies.
    // Assigned from JavaScript instead, a missing property is a no-op, and
    // the try/catch takes the rest. Worst case this function does nothing
    // and we are exactly where we were.
    // KNOWN, UNRESOLVED: under Fiat colours the virtual keyboard comes out
    // pale green. Two guesses at which role causes it have both been wrong --
    // it is not highlightBackgroundColor. The likeliest remaining suspect is
    // highlightColor, which the keyboard may tint its light keys with once
    // colorScheme is forced to DarkOnLight. Cosmetic, one mode only, and it
    // waits for evidence rather than a third guess.
    function applyPalette(item) {
        if (item === null || item === undefined) return
        var p = item.palette
        if (p === undefined || p === null) return
        try { p.colorScheme = ambient ? Theme.colorScheme : Theme.DarkOnLight } catch (e) { }
        try { p.primaryColor = primaryText } catch (e) { }
        try { p.secondaryColor = secondaryText } catch (e) { }
        try { p.highlightColor = accent } catch (e) { }
        try { p.secondaryHighlightColor = Theme.rgba(accent, 0.6) } catch (e) { }
        // NOT the accent. This role is what the virtual keyboard paints its
        // keys with, and a 30% moss over light paper made the whole keyboard
        // pale green. It is the same role that tints selected text, so it has
        // to stay quiet: a neutral wash serves both and shouts in neither.
        try { p.highlightBackgroundColor = Theme.rgba(primaryText, 0.12) } catch (e) { }
        try { p.errorColor = wrong } catch (e) { }
        try { p.highlightDimmerColor = ambient ? Theme.highlightDimmerColor : backgroundLow } catch (e) { }
        try { p.overlayBackgroundColor = ambient ? Theme.overlayBackgroundColor : backgroundHigh } catch (e) { }
    }
}
