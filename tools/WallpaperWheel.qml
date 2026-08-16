import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

Item {
    id: wheelRoot

    // Bind these to whatever size your window/container is
    width: 800
    height: 800

    // The maximum radius of the wheel (leaving a 40px margin)
    readonly property real maxRadius: Math.min(width, height) / 2 - 40

    // ⚠️ CHANGE THIS if your wallpaper path is different
    property string cachePath: FileUtils.trimFileProtocol(Directories.pictures) + "/Wallpapers/.oklab_cache.json"

    ListModel {
        id: wheelModel
    }

    // 1. Read and Parse the JSON Cache
    Process {
        id: readCacheProc
        command: ["cat", wheelRoot.cachePath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    // Quickshell injects the output into the 'text' variable automatically
                    let data = JSON.parse(text);
                    wheelModel.clear();

                    // Find the most vibrant wallpaper to normalize the wheel's radius
                    let maxChroma = 0.001;
                    for (let key in data) {
                        if (data[key].C > maxChroma) maxChroma = data[key].C;
                    }

                    // Populate the model
                    for (let key in data) {
                        let item = data[key];
                        wheelModel.append({
                            "filePath": item.path,
                            "type": item.type,
                            "hue": item.h,
                            "normalizedRadius": item.C / maxChroma
                        });
                    }
                } catch(e) {
                    console.error("⚠️ Failed to parse OKLAB cache. Did the Python script run?", e);
                }
            }
        }
    }

    // Trigger the read when the UI loads
    Component.onCompleted: readCacheProc.exec()

    // 2. The Visual Guide (Optional, draws a faint circle behind the wallpapers)
    Rectangle {
        anchors.centerIn: parent
        width: wheelRoot.maxRadius * 2
        height: wheelRoot.maxRadius * 2
        radius: width / 2
        color: "transparent"
        border.color: "rgba(255, 255, 255, 0.05)"
        border.width: 2
    }

    // 3. The Wallpaper Scatter Plot
    Repeater {
        model: wheelModel
        delegate: Item {
            id: delegateItem

            // TRIGONOMETRY: Polar (Hue, Chroma) to Cartesian (x, y)
            readonly property real angleRad: model.hue * Math.PI / 180
            readonly property real dist: model.normalizedRadius * wheelRoot.maxRadius

            // Position relative to the center of the wheel
            x: (wheelRoot.width / 2) + (dist * Math.cos(angleRad)) - (width / 2)
            y: (wheelRoot.height / 2) + (dist * Math.sin(angleRad)) - (height / 2)

            width: hoverHandler.hovered ? 160 : 64
            height: hoverHandler.hovered ? 90 : 64

            // Bring hovered items to the front so they don't get trapped under others
            z: hoverHandler.hovered ? 100 : Math.floor(dist)

            // Smooth scaling animation on hover
            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: "#1E1E2E" // Catppuccin Base fallback
                border.color: hoverHandler.hovered ? "#89B4FA" : "rgba(255,255,255,0.2)"
                border.width: hoverHandler.hovered ? 2 : 1
                clip: true

                // The Static Image Thumbnail
                Image {
                    anchors.fill: parent
                    source: "file://" + model.filePath

                    // CRITICAL: Forces QML to load a tiny version into RAM, preventing OOM crashes
                    sourceSize.width: 256
                    sourceSize.height: 256
                    fillMode: Image.PreserveAspectCrop

                    // Hide if it's a video and we are actively hovering it
                    visible: !(model.type === "video" && hoverHandler.hovered)
                }

                // The Lazy-Loaded Video Player
                Loader {
                    anchors.fill: parent
                    // Only exist in memory IF it's a video AND the mouse is currently hovering
                    active: model.type === "video" && hoverHandler.hovered
                    sourceComponent: Component {
                        VideoOutput {
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                            MediaPlayer {
                                source: "file://" + model.filePath
                                autoPlay: true
                                loops: MediaPlayer.Infinite
                                audioOutput: AudioOutput { muted: true } // Don't blast audio on hover
                            }
                        }
                    }
                }
            }

            HoverHandler {
                id: hoverHandler
            }

            TapHandler {
                onTapped: {
                    // This is where we will hook back into end4's logic in Phase 3
                    console.log("Selected Wallpaper:", model.filePath, "| Type:", model.type)
                }
            }
        }
    }
}