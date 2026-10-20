const { spawn } = require('node:child_process');
const { sequenceSegments } = require('../Trainer.js');
const [character, speed, hz, loudness] = process.argv.slice(2);
const frequency = Number(hz), volume = Number(loudness);
if (!Number.isFinite(frequency) || frequency < 300 || frequency > 1200 || !Number.isFinite(volume) || volume < 0 || volume > 100) process.exit(2);
const rate = 48000;
const segments = sequenceSegments(character, Number(speed));
const frames = segments.reduce((n, s) => n + Math.round(s.seconds * rate), 0);
const pcm = Buffer.alloc(frames * 2);
let offset = 0;
for (const segment of segments) {
  const length = Math.round(segment.seconds * rate);
  for (let i = 0; i < length; i++) {
    // Five-millisecond attack/release prevents clicks at tone boundaries.
    const envelope = Math.min(1, i / 240, (length - 1 - i) / 240);
    const sample = segment.tone ? Math.sin(2 * Math.PI * frequency * i / rate) * envelope * volume / 100 * 12000 : 0;
    pcm.writeInt16LE(Math.round(sample), (offset + i) * 2);
  }
  offset += length;
}
if (process.env.CW_AUDIO_DUMP === '1') { process.stdout.write(pcm); }
else {
  const player = spawn('paplay', ['--raw', '--format=s16le', '--rate=48000', '--channels=1', '--client-name=CW Quest'], {stdio: ['pipe', 'ignore', 'inherit']});
  const stop = () => { player.kill('SIGTERM'); };
  process.on('SIGTERM', stop); process.on('SIGINT', stop);
  player.on('error', error => { console.error(error.message); process.exitCode = 1; });
  player.stdin.on('error', () => {});
  player.on('exit', code => { process.exitCode = code || 0; });
  player.on('spawn', () => {
    process.stdout.write('CW_READY\n');
    player.stdin.end(pcm);
  });
}
