import QtQuick
import qs.Commons

// A stylized tone trace with a subtle visual noise floor between CW pulses.
Item {
  id: root
  property bool active: false
  property bool transmitting: false
  property var segments: []
  property real startedAt: 0
  property real frequency: 700
  implicitHeight: 56
  clip: true
  onActiveChanged: display.requestPaint()
  onTransmittingChanged: display.requestPaint()

  function begin(timing, hz) {
    segments = timing;
    frequency = hz;
    startedAt = Date.now();
    transmitting = true;
  }
  function sample(now) {
    if (!transmitting)
      return false;
    var elapsed = (now - startedAt) / 1000;
    for (var i = 0; i < segments.length; i++) {
      if (elapsed < segments[i].seconds)
        return segments[i].tone;
      elapsed -= segments[i].seconds;
    }
    return false;
  }
  Timer {
    interval: 16
    running: root.active
    repeat: true
    onTriggered: display.requestPaint()
  }
  Canvas {
    id: display
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext('2d');
      ctx.clearRect(0, 0, width, height);
      var now = Date.now();
      var sounding = root.active && root.sample(now);
      var amplitude = sounding ? Math.min(18, height * 0.32) : 0;
      var cycles = root.frequency / 100;
      var phase = (now - root.startedAt) / 1000 * Math.PI * 8;
      ctx.strokeStyle = String(Color.accent);
      ctx.globalAlpha = sounding ? 1 : 0.35;
      ctx.lineWidth = 2;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.beginPath();
      for (var x = 2; x <= width - 2; x++) {
        var position = (x - 2) / Math.max(1, width - 4);
        // Fade amplitude at the ends so the trace joins the center line.
        var envelope = Math.min(1, position * 10, (1 - position) * 10);
        // Gentle drift gives the trace a live noise floor; audio is unchanged.
        var time = now / 1000;
        var noise = root.active ? 0.65 * Math.sin(x * 0.61 + time * 8.1) + 0.35 * Math.sin(x * 1.17 - time * 6.3) + 0.20 * Math.sin(x * 0.23 + time * 11.7) : 0;
        var y = height / 2 + (Math.sin(position * Math.PI * 2 * cycles - phase) * amplitude + noise) * envelope;
        if (x === 2)
          ctx.moveTo(x, y);
        else
          ctx.lineTo(x, y);
      }
      ctx.stroke();
    }
  }
}
