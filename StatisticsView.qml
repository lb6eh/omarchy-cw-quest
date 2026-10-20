pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "Trainer.js" as Trainer

ColumnLayout {
  id: root
  required property var summary
  spacing: 10
  component Label: Text {
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    wrapMode: Text.WordWrap
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: 13
  }
  Label {
    text: "YOUR CW LOGBOOK"
    font.bold: true
    color: Color.accent
  }
  Label {
    text: root.summary.attempts + " characters answered · " + (root.summary.accuracy === null ? "—" : root.summary.accuracy + "%") + " correct\n" + root.summary.correct + " correct · " + root.summary.wrong + " missed\n" + root.summary.plays + " character playbacks"
  }
  Label {
    text: "CW LISTENING TIME\n" + Trainer.formatDuration(root.summary.listeningMs)
    color: Color.accent
  }
  Label {
    text: Trainer.troubleText(root.summary)
  }
  Label {
    text: "PER SOUND · MOST MISTAKES FIRST"
    font.bold: true
    Layout.topMargin: 8
    visible: root.summary.rows.length > 0
  }
  Repeater {
    model: root.summary.rows
    Rectangle {
      id: card
      required property var modelData
      Layout.fillWidth: true
      implicitHeight: details.implicitHeight + 20
      radius: Style.cornerRadius
      color: Util.alpha(Color.foreground, 0.06)
      Label {
        id: details
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 10
        text: card.modelData.character + "  ·  " + (card.modelData.accuracy === null ? "not answered yet" : card.modelData.accuracy + "% correct") + "\n" + card.modelData.attempts + " answers · " + card.modelData.wrong + " missed · " + card.modelData.plays + " plays" + "\nCW heard: " + Trainer.formatDuration(card.modelData.listeningMs)
      }
    }
  }
  Label {
    text: "Statistics start with this update (or your last reset). Includes answers from unfinished quests and lesson replays. Timing adds dots, dashes and internal gaps at the WPM used for each playback. It excludes thinking time, test tones and GJ celebrations."
    font.pixelSize: 11
    opacity: 0.6
  }
}
