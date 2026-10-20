import QtQuick
import Quickshell.Io
import qs.Ui as Ui

Ui.BarWidget {
  id: root
  moduleName: "lb6eh.cw-quest"
  readonly property bool opened: loader.item ? loader.item.opened : false
  readonly property bool popoutSwitchClosing: loader.item ? loader.item.popoutSwitchClosing : false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  function open() {
    if (loader.item)
      loader.item.open();
  }
  function close() {
    if (loader.item)
      loader.item.close();
  }
  function closeForPopoutSwitch() {
    if (loader.item)
      loader.item.closeForPopoutSwitch();
  }
  function inject() {
    if (!loader.item)
      return;
    loader.item.bar = root.bar;
    loader.item.anchorItem = button;
    loader.item.hostWidget = root;
  }
  onBarChanged: inject()
  Loader {
    id: loader
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: root.inject()
  }
  Ui.BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "·−"
    tooltipText: "CW Quest · learn Morse"
    onPressed: function (b) {
      if (loader.item)
        loader.item.toggle();
    }
  }
  IpcHandler {
    target: "lb6eh.cw-quest"
    function open(): void {
      root.open();
    }
    function close(): void {
      root.close();
    }
    function toggle(): void {
      if (loader.item)
        loader.item.toggle();
    }
  }
}
