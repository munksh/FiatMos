pragma Singleton

import QtQuick 2.0
import Nemo.Configuration 1.0
import "Lookup.js" as Lookup

// Which services Look up may ask, and whether the user has chosen yet.
//
// Kept on the phone (dconf, like the colour switch) and deliberately NOT in
// the export: it is a consent, and a consent given on one phone is not one the
// next phone has been asked for.
//
// Until the user has confirmed the list once, nothing is enabled at all --
// enabledIds() is empty, whatever the switches say -- so no page can contact
// a service by mistake before the person has seen what each one receives.
// The switches themselves start out as Lookup.SERVICES says: the libraries on,
// Google off.

QtObject {
    id: s

    property ConfigurationValue chosenConfig: ConfigurationValue {
        key: "/apps/harbour-fiatmos/lookup/chosen"
        defaultValue: false
    }
    property ConfigurationValue openlibraryConfig: ConfigurationValue {
        key: "/apps/harbour-fiatmos/lookup/openlibrary"
        defaultValue: true
    }
    property ConfigurationValue librisConfig: ConfigurationValue {
        key: "/apps/harbour-fiatmos/lookup/libris"
        defaultValue: true
    }
    property ConfigurationValue dnbConfig: ConfigurationValue {
        key: "/apps/harbour-fiatmos/lookup/dnb"
        defaultValue: true
    }
    property ConfigurationValue bnfConfig: ConfigurationValue {
        key: "/apps/harbour-fiatmos/lookup/bnf"
        defaultValue: true
    }
    property ConfigurationValue googleConfig: ConfigurationValue {
        key: "/apps/harbour-fiatmos/lookup/google"
        defaultValue: false
    }

    // Has the list been confirmed?
    readonly property bool chosen: chosenConfig.value === true

    // What the switch for this service says. Not what is allowed: see enabledIds().
    function wanted(id) {
        if (id === "openlibrary") return openlibraryConfig.value === true
        if (id === "libris") return librisConfig.value === true
        if (id === "dnb") return dnbConfig.value === true
        if (id === "bnf") return bnfConfig.value === true
        if (id === "google") return googleConfig.value === true
        return false
    }

    // The services that may be asked, in the order they are listed. Empty
    // until the list has been confirmed.
    function enabledIds() {
        var out = []
        if (!s.chosen) return out
        for (var i = 0; i < Lookup.SERVICES.length; i++) {
            if (s.wanted(Lookup.SERVICES[i].id)) out.push(Lookup.SERVICES[i].id)
        }
        return out
    }

    // For a label that has to update when a switch does.
    readonly property int enabledCount: !chosen ? 0
        : (openlibraryConfig.value === true ? 1 : 0)
        + (librisConfig.value === true ? 1 : 0)
        + (dnbConfig.value === true ? 1 : 0)
        + (bnfConfig.value === true ? 1 : 0)
        + (googleConfig.value === true ? 1 : 0)

    // Store a choice, { openlibrary: true, ... }. The confirmation goes last,
    // so anything that reacts to it sees the switches already settled.
    function apply(choice) {
        openlibraryConfig.value = choice.openlibrary === true
        librisConfig.value = choice.libris === true
        dnbConfig.value = choice.dnb === true
        bnfConfig.value = choice.bnf === true
        googleConfig.value = choice.google === true
        chosenConfig.value = true
    }
}
