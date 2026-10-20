import QtQuick
import qs.Commons

Item {
  id: root
  property bool active: false
  property var particles: []
  property real startedAt: 0
  clip: true
  visible: particles.length > 0
  onActiveChanged: if (!active)
    stop()

  function stop() {
    animation.stop();
    particles = [];
    canvas.requestPaint();
  }
  function burst() {
    var pieces = [];
    for (var i = 0; i < 48; i++) {
      pieces.push({
        vx: (Math.random() - 0.5) * 230,
        vy: -100 - Math.random() * 140,
        spin: (Math.random() - 0.5) * 10,
        color: i % 3 === 0 ? String(Color.accent) : i % 3 === 1 ? '#f5d876' : '#77cbb4',
        size: 3 + Math.random() * 3
      });
    }
    particles = pieces;
    startedAt = Date.now();
    animation.start();
    canvas.requestPaint();
  }
  Timer {
    id: animation
    interval: 16
    repeat: true
    onTriggered: {
      if (Date.now() - root.startedAt > 2600)
        root.stop();
      else
        canvas.requestPaint();
    }
  }
  Canvas {
    id: canvas
    anchors.fill: parent
    onPaint: {
      var ctx = getContext('2d');
      ctx.clearRect(0, 0, width, height);
      var t = (Date.now() - root.startedAt) / 1000;
      for (var i = 0; i < root.particles.length; i++) {
        var p = root.particles[i];
        var x = width / 2 + p.vx * t;
        var y = height * 0.55 + p.vy * t + 150 * t * t;
        ctx.save();
        ctx.translate(x, y);
        ctx.rotate(p.spin * t);
        ctx.globalAlpha = Math.max(0, Math.min(1, (2.6 - t) / 0.6));
        ctx.fillStyle = p.color;
        ctx.fillRect(-p.size / 2, -p.size, p.size, p.size * 2);
        ctx.restore();
      }
    }
  }
}
