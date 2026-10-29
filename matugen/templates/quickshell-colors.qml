pragma Singleton
import QtQuick

QtObject {
    property color bg0: "{{ colors.surface_container_lowest.default.hex }}"
    property color bg1: "{{ colors.surface_container_low.default.hex }}"
    property color bg2: "{{ colors.surface_container.default.hex }}"
    property color surfaceBorder: "{{ colors.outline_variant.default.hex }}"
    property color text: "{{ colors.on_surface.default.hex }}"
    property color textAlt: "{{ colors.outline.default.hex }}"
    property color accent: "{{ colors.primary.default.hex }}"
    property color accentInactive: "{{ colors.surface_variant.default.hex }}"
}
