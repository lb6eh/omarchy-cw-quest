pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui
import "Trainer.js" as Trainer

Ui.Panel {
  id: root
  moduleName: "lb6eh.cw-quest"
  ipcTarget: "lb6eh.cw-quest"
  manageIpc: false
  property var anchorItem: null
  property var hostWidget: null
  property var profile: Trainer.newProfile()
  property var round: null
  property string page: "lessons"
  property string progressPage: "statistics"
  property var playback: null
  property string feedback: ""
  property string errorText: ""
  property bool loaded: false
  property var transmissionSegments: []
  property bool heard: false
  property bool confirmReset: false
  property bool resetDone: false
  property bool celebrationShown: false
  property bool awaitingNext: false
  property string pendingWrite: ""
  readonly property string helperDirectory: decodeURIComponent(String(Qt.resolvedUrl("helpers/")).replace(/^file:\/\//, ""))
  readonly property var globalStats: Trainer.statistics(profile)
  readonly property var lessonStats: Trainer.roundStatistics(round)
  readonly property var achievements: Trainer.achievements(profile)
  readonly property int level: Math.floor(profile.xp / 250) + 1

  function stopAudio() {
    finishPlayback(false);
    audio.running = false;
  }
  function finishPlayback(completed) {
    var current = playback;
    playback = null;
    if (!current || !current.startedAt)
      return;
    var ms = completed ? current.durationMs : Math.min(current.durationMs, Math.max(0, Date.now() - current.startedAt));
    if (!ms)
      return;
    profile = Trainer.recordPlayback(profile, current.character, ms);
    if (round) {
      var updated = JSON.parse(JSON.stringify(round));
      updated.listeningMs += Math.round(ms);
      updated.plays++;
      round = updated;
    }
    save();
  }
  function close() {
    feedbackTimer.stop();
    stopAudio();
    root.controller.hide();
  }
  function save() {
    if (!loaded)
      return;
    pendingWrite = JSON.stringify(profile);
    flush();
  }
  function flush() {
    if (writer.running || !pendingWrite)
      return;
    writer.command = ["node", helperDirectory + "state.cjs", "write"];
    writer.stdinEnabled = true;
    writer.running = true;
  }
  function start(lesson) {
    celebrationShown = false;
    confetti.stop();
    feedbackTimer.stop();
    stopAudio();
    round = Trainer.newRound(lesson);
    var copy = JSON.parse(JSON.stringify(profile));
    copy.lastLesson = lesson;
    profile = Trainer.restore(copy);
    page = "play";
    keyFocus.forceActiveFocus();
    feedback = "Listen to the sound. Type the character you hear.";
    heard = false;
    awaitingNext = false;
    save();
  }
  function play(character) {
    if (audio.running || feedbackTimer.running)
      return;
    var target = character || (round && !round.done ? round.queue[round.index] : "K");
    errorText = "";
    transmissionSegments = Trainer.sequenceSegments(target, profile.settings.wpm);
    playback = page === "play" && round && !round.done && target.length === 1 ? {
      character: target,
      durationMs: Trainer.durationMs(target, profile.settings.wpm),
      startedAt: 0
    } : null;
    audio.command = ["node", helperDirectory + "audio.cjs", target, String(profile.settings.wpm), String(profile.settings.frequency), String(profile.settings.volume)];
    heard = false;
    audio.running = true;
    keyFocus.forceActiveFocus();
  }
  function submit(text) {
    if (page !== "play" || !round || round.done || awaitingNext || audio.running || !heard)
      return;
    var expected = round.queue[round.index];
    profile = Trainer.recordAnswer(profile, expected, text);
    round = Trainer.answer(round, text);
    feedback = text.toUpperCase() === expected ? "Correct! +" + (10 + Math.min(10, (round.combo - 1) * 2)) + " XP" : "That was " + expected + "  " + Trainer.MORSE[expected] + ". Listen to its rhythm again.";
    awaitingNext = true;
    heard = false;
    if (text.toUpperCase() === expected)
      feedbackTimer.restart();
    if (round.done) {
      profile = Trainer.finish(profile, round);
      save();
      if (!feedbackTimer.running)
        Qt.callLater(celebrate);
    }
    save();
  }
  function celebrate() {
    if (celebrationShown || !opened || page !== "play" || !round || !round.done)
      return;
    celebrationShown = true;
    confetti.burst();
    play("GJ");
  }
  function continueLesson() {
    if (page !== "play" || !round || feedbackTimer.running)
      return;
    if (round.done) {
      if (round.lesson < Trainer.ORDER.length - 2)
        start(round.lesson + 1);
    } else if (awaitingNext)
      nextSound();
  }
  function nextSound() {
    feedbackTimer.stop();
    awaitingNext = false;
    feedback = "Listen, then type your answer.";
    play();
  }
  function resetProgress() {
    if (!loaded || !confirmReset)
      return;
    feedbackTimer.stop();
    stopAudio();
    confetti.stop();
    round = null;
    heard = false;
    awaitingNext = false;
    celebrationShown = false;
    profile = Trainer.resetProgress(profile);
    confirmReset = false;
    resetDone = true;
    save();
  }
  function setting(name, value) {
    var copy = JSON.parse(JSON.stringify(profile));
    copy.settings[name] = value;
    profile = Trainer.restore(copy);
    save();
  }
  onPageChanged: {
    stopAudio();
    feedbackTimer.stop();
    confirmReset = false;
    resetDone = false;
  }
  onOpenedChanged: if (!opened) {
    confirmReset = false;
    feedbackTimer.stop();
    stopAudio();
  }

  Timer {
    id: feedbackTimer
    interval: 1000
    onTriggered: {
      if (root.page === "play" && root.round && !root.round.done)
        root.nextSound();
      else if (root.round && root.round.done)
        root.celebrate();
    }
  }

  Process {
    id: reader
    command: ["node", root.helperDirectory + "state.cjs", "read"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.profile = Trainer.restore(JSON.parse(text));
        } catch (e) {
          root.errorText = "Could not read saved progress. Defaults loaded.";
        }
      }
    }
    onExited: function (code) {
      root.loaded = true;
      if (code !== 0)
        root.errorText = "Progress could not be loaded. Check Node.js and your state directory.";
    }
  }
  Process {
    id: writer
    stdinEnabled: true
    onStarted: {
      write(root.pendingWrite);
      root.pendingWrite = "";
      stdinEnabled = false;
    }
    onExited: function (code) {
      if (code !== 0)
        root.errorText = "Progress could not be saved. Check your state directory.";
      Qt.callLater(root.flush);
    }
  }
  Process {
    id: audio
    stdout: SplitParser {
      onRead: function (line) {
        if (line === "CW_READY") {
          if (root.playback)
            root.playback.startedAt = Date.now();
          waveform.begin(root.transmissionSegments, root.profile.settings.frequency);
        }
      }
    }
    onExited: function (code) {
      if (code === 0)
        root.finishPlayback(true);
      else
        root.playback = null;
      waveform.transmitting = false;
      if (code === 0 && root.opened)
        root.heard = true;
      else if (code !== 0 && root.opened)
        root.errorText = "Audio failed. Install Node.js and paplay, and check your audio output.";
    }
  }

  component QuestButton: Controls.Button {
    id: control
    implicitWidth: 80
    implicitHeight: 32
    Layout.minimumWidth: 0
    font.pixelSize: 13
    font.family: Style.font.family
    contentItem: Text {
      text: control.text
      font: control.font
      color: control.highlighted ? Color.popups.background : Color.foreground
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }
    background: Rectangle {
      radius: Style.cornerRadius
      color: control.highlighted ? Color.accent : Util.alpha(Color.foreground, control.hovered ? 0.14 : 0.07)
      opacity: control.enabled ? 1 : 0.4
      border.width: control.activeFocus ? 2 : 0
      border.color: Color.accent
    }
  }
  component Caption: Text {
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    font.family: Style.font.family
    color: Color.foreground
    font.pixelSize: 13
    wrapMode: Text.WordWrap
  }

  Ui.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    contentWidth: fittedContentWidth(380)
    contentHeight: fittedContentHeight(420)
    padding: 12
    focusTarget: keyFocus

    Item {
      id: keyFocus
      anchors.fill: parent
      focus: true
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
          root.close();
          event.accepted = true;
        } else if (root.page === "play" && event.key === Qt.Key_Space) {
          if (root.awaitingNext && !root.round.done)
            root.play(root.round.answers[root.round.answers.length - 1].expected);
          else if (!root.round.done)
            root.play();
          event.accepted = true;
        } else if (root.page === "play" && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
          if (!event.isAutoRepeat)
            root.continueLesson();
          event.accepted = true;
        } else if (root.page === "play" && event.text && Trainer.MORSE[event.text.toUpperCase()]) {
          root.submit(event.text);
          event.accepted = true;
        }
      }
    }
    ColumnLayout {
      id: panelContent
      clip: true
      anchors.fill: parent
      spacing: 8
      RowLayout {
        Layout.fillWidth: true
        ColumnLayout {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: "CW QUEST"
            font.family: Style.font.family
            font.pixelSize: 19
            font.bold: true
            font.letterSpacing: 2
            color: Color.accent
          }
          Caption {
            text: "Small lessons. Stronger signals."
            opacity: 0.65
          }
        }
        Item {
          Layout.fillWidth: true
        }
        Caption {
          Layout.fillWidth: false
          text: "LVL " + root.level + "\n" + root.profile.xp + " XP"
          horizontalAlignment: Text.AlignRight
          font.bold: true
        }
      }
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 4
        radius: 2
        color: Util.alpha(Color.foreground, 0.08)
        Rectangle {
          height: parent.height
          width: parent.width * (root.profile.xp % 250) / 250
          radius: 2
          color: Color.accent
        }
      }
      RowLayout {
        Layout.fillWidth: true
        QuestButton {
          text: "Lessons"
          Layout.fillWidth: true
          highlighted: root.page === "lessons"
          onClicked: {
            root.stopAudio();
            root.page = "lessons";
          }
        }
        QuestButton {
          text: "Progress"
          Layout.fillWidth: true
          highlighted: root.page === "progress"
          onClicked: {
            root.stopAudio();
            root.page = "progress";
          }
        }
        QuestButton {
          text: "Setup"
          Layout.fillWidth: true
          highlighted: root.page === "setup"
          onClicked: {
            root.stopAudio();
            root.page = "setup";
          }
        }
      }
      Caption {
        visible: !!root.errorText
        text: root.errorText
        color: Color.urgent
        Layout.fillWidth: true
      }
      Controls.ScrollView {
        id: pageScroll
        objectName: "questPageScroll"
        contentHeight: pages.height
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        clip: true
        contentWidth: availableWidth
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
        StackLayout {
          id: pages
          width: pageScroll.availableWidth
          height: root.page === "play" || root.page === "lessons" ? pageScroll.availableHeight : Math.max(pageScroll.availableHeight, children[currentIndex].implicitHeight)
          currentIndex: root.page === "lessons" ? 0 : root.page === "play" ? 1 : root.page === "progress" ? 2 : 3
          ColumnLayout {
            Caption {
              text: "CHOOSE YOUR NEXT SIGNAL"
              font.bold: true
              font.letterSpacing: 1
            }
            Caption {
              text: "10 sounds per quest · every lesson is open\nGold: 100% · Silver: 90% · Bronze: 70%"
              opacity: 0.65
              Layout.fillWidth: true
            }
            Controls.ScrollView {
              id: lessonScroll
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              contentWidth: availableWidth
              GridLayout {
                width: lessonScroll.availableWidth
                columns: 4
                columnSpacing: 8
                rowSpacing: 8
                Repeater {
                  model: Trainer.ORDER.length - 1
                  QuestButton {
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 48
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    highlighted: root.profile.lastLesson === index
                    text: String(index + 1).padStart(2, '0') + " · " + (index === 0 ? "K M" : Trainer.ORDER[index + 1]) + "\n" + ["○ ○ ○", "● ○ ○", "● ● ○", "● ● ●"][root.profile.medals[index] || 0]
                    enabled: root.loaded
                    onClicked: root.start(index)
                  }
                }
              }
            }
          }
          ColumnLayout {
            Layout.minimumHeight: 0
            spacing: 6
            Caption {
              text: root.round ? "LESSON " + (root.round.lesson + 1) + (root.round.done ? " · QUEST COMPLETE" : " / " + Trainer.characters(root.round.lesson).split('').join('')) : ""
              Layout.fillWidth: true
              opacity: 0.7
            }
            Item {
              Layout.fillHeight: true
            }
            Waveform {
              id: waveform
              visible: !root.round || !root.round.done
              Layout.fillWidth: true
              Layout.preferredHeight: 56
              active: root.opened && root.page === "play"
            }
            Text {
              visible: feedbackTimer.running || (root.round && root.round.done) || root.awaitingNext
              Layout.alignment: Qt.AlignHCenter
              text: feedbackTimer.running ? "✓" : root.round && root.round.done ? root.round.correct * 10 + "%" : root.awaitingNext ? "↺" : "?"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: 24
              font.bold: true
            }
            Caption {
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              text: feedbackTimer.running ? root.feedback : root.round && root.round.done ? ["Keep tuning your ears", "Bronze signal", "Silver signal", "Perfect signal!"][Trainer.medal(root.round.correct)] : root.feedback
            }
            Caption {
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              opacity: 0.65
              text: root.round ? (root.round.done ? "+" + (root.round.xp + (root.round.correct >= 9 ? 30 : 0)) + " XP · longest correct streak " + root.round.bestCombo : "Sound " + (root.round.index + 1) + " / 10   ·   correct streak " + root.round.combo + "   ·   " + root.round.xp + " XP") : ""
            }
            Item {
              Layout.fillHeight: true
            }
            Caption {
              visible: root.round && root.round.done && !feedbackTimer.running
              text: root.lessonStats.correct + " / " + root.lessonStats.attempts + " correct · " + root.lessonStats.plays + " plays\nCW heard: " + Trainer.formatDuration(root.lessonStats.listeningMs) + "\n" + Trainer.troubleText(root.lessonStats)
              font.pixelSize: 12
              horizontalAlignment: Text.AlignHCenter
            }
            QuestButton {
              Layout.fillWidth: true
              highlighted: true
              text: feedbackTimer.running ? (root.round.done ? "Correct! Quest complete…" : "Next sound in 1 second…") : root.round && root.round.done ? "Play again" : root.awaitingNext ? "Next sound  ↵" : audio.running ? "Transmitting…" : "Listen  [Space]"
              enabled: !audio.running && !feedbackTimer.running
              onClicked: {
                if (root.round.done)
                  root.start(root.round.lesson);
                else if (root.awaitingNext)
                  root.nextSound();
                else
                  root.play();
              }
            }
            QuestButton {
              Layout.fillWidth: true
              visible: root.awaitingNext && root.round && !root.round.done && !feedbackTimer.running
              text: "Hear that answer again  [Space]"
              enabled: !audio.running && !feedbackTimer.running
              onClicked: root.play(root.round.answers[root.round.answers.length - 1].expected)
            }
            QuestButton {
              Layout.fillWidth: true
              visible: root.round && root.round.done && !feedbackTimer.running
              text: "Next lesson  [Enter]"
              enabled: root.round && root.round.lesson < Trainer.ORDER.length - 2
              onClicked: root.continueLesson()
            }
            Caption {
              visible: !root.round || !root.round.done
              text: "Space replays · correct answers auto-advance.\nAfter a miss, Enter continues · Esc closes."
              opacity: 0.6
              Layout.fillWidth: true
            }
          }
          ColumnLayout {
            Caption {
              text: "YOUR SIGNAL IS GETTING STRONGER"
              visible: root.progressPage === "achievements"
              font.bold: true
            }
            Text {
              visible: root.progressPage === "achievements"
              text: root.profile.xp + " XP"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: 42
              font.bold: true
            }
            Caption {
              text: root.profile.rounds + " completed quests · longest correct streak " + root.profile.bestCombo
            }
            RowLayout {
              Layout.fillWidth: true
              QuestButton {
                Layout.fillWidth: true
                text: "Statistics"
                highlighted: root.progressPage === "statistics"
                onClicked: root.progressPage = "statistics"
              }
              QuestButton {
                Layout.fillWidth: true
                text: "Achievements"
                highlighted: root.progressPage === "achievements"
                onClicked: root.progressPage = "achievements"
              }
            }
            StatisticsView {
              visible: root.progressPage === "statistics"
              Layout.fillWidth: true
              summary: root.globalStats
            }
            ColumnLayout {
              visible: root.progressPage === "achievements"
              Layout.fillWidth: true
              Caption {
                text: "ACHIEVEMENTS · " + root.achievements.filter(function (a) {
                  return a.earned;
                }).length + " / " + root.achievements.length
                font.bold: true
                Layout.topMargin: 20
              }
              Repeater {
                model: root.achievements
                Rectangle {
                  required property var modelData
                  Layout.fillWidth: true
                  implicitHeight: Math.max(56, achievementText.implicitHeight + 20)
                  radius: Style.cornerRadius
                  color: Util.alpha(Color.foreground, 0.06)
                  Caption {
                    id: achievementText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    text: (parent.modelData.earned ? "★  " : "○  ") + parent.modelData.name + "\n     " + parent.modelData.detail
                    color: parent.modelData.earned ? Color.accent : Color.foreground
                    opacity: parent.modelData.earned ? 1 : 0.55
                  }
                }
              }
              Item {
                Layout.fillHeight: true
              }
            }
          }
          ColumnLayout {
            Caption {
              text: "TUNE YOUR STATION"
              font.bold: true
              font.letterSpacing: 1
            }
            Caption {
              text: "Learn each character as a rhythm. Start at 20 WPM; replay as often as you need."
              opacity: 0.65
              Layout.fillWidth: true
            }
            Caption {
              text: "Character speed · words per minute"
              Layout.topMargin: 16
            }
            Controls.SpinBox {
              from: 5
              to: 50
              value: root.profile.settings.wpm
              enabled: root.loaded
              onValueModified: root.setting("wpm", value)
            }
            Caption {
              text: "Tone frequency · Hz"
            }
            Controls.SpinBox {
              from: 300
              to: 1200
              stepSize: 25
              value: root.profile.settings.frequency
              enabled: root.loaded
              onValueModified: root.setting("frequency", value)
            }
            Caption {
              text: "App volume · " + root.profile.settings.volume + "%"
            }
            Controls.Slider {
              Layout.fillWidth: true
              from: 0
              to: 100
              stepSize: 1
              value: root.profile.settings.volume
              enabled: root.loaded
              onMoved: root.setting("volume", Math.round(value))
            }
            QuestButton {
              Layout.fillWidth: true
              text: audio.running ? "Transmitting…" : "Test tone · K  − · −"
              enabled: !audio.running && !feedbackTimer.running
              onClicked: root.play("K")
            }
            QuestButton {
              Layout.fillWidth: true
              text: "Restore audio defaults"
              enabled: root.loaded
              onClicked: {
                root.setting("wpm", 20);
                root.setting("frequency", 700);
                root.setting("volume", 80);
              }
            }
            Caption {
              text: "Settings and completed quests save automatically.\nLeaving a quest keeps your completed progress; unfinished rounds earn no XP."
              opacity: 0.65
              Layout.fillWidth: true
            }
            Item {
              Layout.fillHeight: true
            }
            QuestButton {
              Layout.fillWidth: true
              text: "Reset lesson progress"
              enabled: root.loaded && !root.confirmReset
              onClicked: {
                root.confirmReset = true;
                root.resetDone = false;
              }
            }
            Caption {
              visible: root.resetDone
              text: "Progress reset. Audio settings kept."
              color: Color.accent
            }
          }
        }
      }
      Caption {
        Layout.fillWidth: true
        text: "● " + root.profile.settings.wpm + " WPM · " + root.profile.settings.frequency + " Hz · CW / KOCH"
        opacity: 0.45
        font.pixelSize: 11
      }
    }
    Item {
      id: resetConfirmation
      anchors.fill: parent
      visible: root.confirmReset
      z: 20
      onVisibleChanged: if (visible)
        cancelReset.forceActiveFocus()
      Rectangle {
        anchors.fill: parent
        color: Color.popups.background
      }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
      }
      ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - 24
        spacing: 12
        Caption {
          text: "ARE YOU SURE?"
          font.bold: true
          font.pixelSize: 18
          color: Color.urgent
        }
        Caption {
          text: "Reset all lesson progress? This clears XP, medals, achievements, completed quests and statistics. Audio settings will be kept."
        }
        QuestButton {
          id: cancelReset
          Layout.fillWidth: true
          text: "Cancel"
          onClicked: {
            root.confirmReset = false;
            keyFocus.forceActiveFocus();
          }
        }
        QuestButton {
          Layout.fillWidth: true
          text: "Yes, reset progress"
          onClicked: {
            root.resetProgress();
            keyFocus.forceActiveFocus();
          }
        }
      }
      Keys.onEscapePressed: {
        root.confirmReset = false;
        keyFocus.forceActiveFocus();
      }
    }
    Confetti {
      id: confetti
      anchors.fill: parent
      z: 10
      active: root.opened && root.page === "play"
    }
  }
}
