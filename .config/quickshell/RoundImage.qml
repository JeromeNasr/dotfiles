// RoundImage.qml — image with rounded corners that fades in when it (re)loads.
import QtQuick
import QtQuick.Effects

Item {
    id: r
    property url source
    property real radius: 8
    readonly property bool ready: img.status === Image.Ready

    Image {
        id: img
        anchors.fill: parent
        source: r.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; smooth: true; mipmap: true
        sourceSize: Qt.size(Math.max(1, r.width * 2), Math.max(1, r.height * 2))
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: msk; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
    }
    Item {
        id: msk
        anchors.fill: parent; visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: r.radius }
    }
}
