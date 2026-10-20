const {test} = require('node:test');
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const T = require('../Trainer.js');

test('40 Koch lessons cover every character once, beginning with K and M', () => {
  assert.equal(T.ORDER.length, 41);
  assert.equal(new Set(T.ORDER).size, 41);
  assert.equal(T.characters(0), 'KM');
  assert.equal(T.characters(39), T.ORDER);
  for (const char of T.ORDER) assert.ok(T.MORSE[char]);
  for (let lesson = 0; lesson < 40; lesson++) {
    const r = T.newRound(lesson, () => 0.5);
    assert.equal(r.queue.length, 10);
    assert.equal(r.queue[0], T.characters(lesson).at(-1));
    assert.ok(r.queue.every(c => T.characters(lesson).includes(c)));
  }
});
test('perfect rounds award combo XP, completion bonus and gold', () => {
  let round = T.newRound(0, () => 0);
  for (const c of round.queue) round = T.answer(round, c.toLowerCase());
  assert.equal(round.correct, 10);
  assert.equal(round.bestCombo, 10);
  const profile = T.finish(T.newProfile(), round);
  assert.equal(profile.xp, 200);
  assert.equal(profile.medals[0], 3);
  assert.equal(profile.rounds, 1);
  assert.deepEqual(T.answer(round, 'K'), round);
});
test('mistakes reset combos; completed medals never regress', () => {
  let round = T.newRound(5, () => 0);
  round = T.answer(round, round.queue[0]);
  round = T.answer(round, '?');
  assert.equal(round.combo, 0);
  while (!round.done) round = T.answer(round, round.queue[round.index]);
  assert.equal(T.medal(round.correct), 2);
  const profile = T.newProfile(); profile.medals[5] = 3;
  assert.equal(T.finish(profile, round).medals[5], 3);
  assert.throws(() => T.finish(profile, T.newRound(0)), /unfinished/);
});
test('corrupt profile data and settings are bounded', () => {
  const p = T.restore({version: 1, xp: -1, lastLesson: 999, medals: {0: 99}, settings: {wpm: 1000, frequency: 'oops', volume: -20}});
  assert.deepEqual(p.settings, {wpm: 50, frequency: 700, volume: 0});
  assert.equal(p.lastLesson, 39);
  assert.equal(p.xp, 0);
  assert.equal(p.medals[0], 3);
  assert.deepEqual(T.restore(null), T.newProfile());
});
test('PARIS timing uses 60ms dots, 180ms dashes and 60ms internal gaps at 20 WPM', () => {
  assert.deepEqual(T.toneSegments('K', 20), [
    {tone: true, seconds: 0.18}, {tone: false, seconds: 0.06},
    {tone: true, seconds: 0.06}, {tone: false, seconds: 0.06}, {tone: true, seconds: 0.18}
  ]);
  assert.equal(T.toneSegments('E', 40)[0].seconds, 0.03);
  assert.throws(() => T.toneSegments('☃', 20), /Unsupported/);
});
test('audio renders 700Hz PCM with ramped tone edges and silent gaps', () => {
  const result = spawnSync(process.execPath, ['helpers/audio.cjs', 'K', '20', '700', '40'], {env: {...process.env, CW_AUDIO_DUMP: '1'}});
  assert.equal(result.status, 0);
  assert.equal(result.stdout.length, 0.54 * 48000 * 2);
  assert.equal(result.stdout.readInt16LE(0), 0);
  const gap = result.stdout.subarray(8640 * 2, 11520 * 2);
  assert.ok(gap.every(byte => byte === 0));
  // A 100ms interior sample contains 70 periods of the requested tone.
  let rising = 0;
  for (let frame = 481; frame < 5280; frame++) {
    if (result.stdout.readInt16LE((frame - 1) * 2) <= 0 && result.stdout.readInt16LE(frame * 2) > 0) rising++;
  }
  assert.ok(rising >= 69 && rising <= 71);
});
test('state helper saves and loads under XDG_STATE_HOME without modifying HOME', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cw-state-test-'));
  const env = {...process.env, XDG_STATE_HOME: directory};
  try {
    const p = T.newProfile(); p.xp = 200; p.settings.frequency = 825;
    const write = spawnSync(process.execPath, ['helpers/state.cjs', 'write'], {env, input: JSON.stringify(p), encoding: 'utf8'});
    assert.equal(write.status, 0, write.stderr);
    const read = spawnSync(process.execPath, ['helpers/state.cjs', 'read'], {env, encoding: 'utf8'});
    assert.equal(read.status, 0, read.stderr);
    assert.equal(JSON.parse(read.stdout).xp, 200);
    assert.equal(JSON.parse(read.stdout).settings.frequency, 825);
    assert.equal(fs.statSync(path.join(directory, 'omarchy-cw-quest/profile.json')).mode & 0o777, 0o600);
    fs.writeFileSync(path.join(directory, 'omarchy-cw-quest/profile.json'), '{broken');
    assert.notEqual(spawnSync(process.execPath, ['helpers/state.cjs', 'read'], {env}).status, 0);
  } finally { fs.rmSync(directory, {recursive: true, force: true}); }
});

test('GJ celebration uses normal Morse characters and a three-dot letter gap', () => {
  const g = T.toneSegments('G', 20), j = T.toneSegments('J', 20);
  assert.deepEqual(T.sequenceSegments('GJ', 20), [...g, {tone: false, seconds: 0.18}, ...j]);
  assert.deepEqual(T.sequenceSegments('K', 20), T.toneSegments('K', 20));
  assert.throws(() => T.sequenceSegments('', 20));
  assert.throws(() => T.sequenceSegments('☃', 20));
  const result = spawnSync(process.execPath, ['helpers/audio.cjs', 'GJ', '20', '700', '40'], {env: {...process.env, CW_AUDIO_DUMP: '1'}});
  assert.equal(result.status, 0);
  const frames = T.sequenceSegments('GJ', 20).reduce((sum, s) => sum + Math.round(s.seconds * 48000), 0);
  assert.equal(result.stdout.length, frames * 2);
});

test('reset clears learning progress and keeps audio settings without mutating the profile', () => {
  const original = T.newProfile();
  Object.assign(original, {xp: 1200, rounds: 12, bestCombo: 10, lastLesson: 8, medals: {0: 3, 8: 2}});
  original.settings = {wpm: 27, frequency: 825, volume: 23};
  const snapshot = JSON.stringify(original);
  const reset = T.resetProgress(original);
  assert.deepEqual(reset, {...T.newProfile(), settings: original.settings});
  assert.equal(JSON.stringify(original), snapshot);
  reset.settings.wpm = 10;
  assert.equal(original.settings.wpm, 27);
});

test('achievements credit saved progress, distinct medals, and milestone boundaries', () => {
  const p = T.newProfile();
  const earned = profile => T.achievements(profile).filter(a => a.earned).map(a => a.name);
  assert.equal(T.achievements(p).length, 18);
  assert.deepEqual(earned(p), []);
  p.rounds = 24;
  assert.ok(!earned(p).includes('Morse before chores'));
  p.rounds = 25;
  assert.ok(earned(p).includes('Morse before chores'));
  p.medals = {0: 3, 1: 3, 2: 3, 3: 3};
  assert.ok(!earned(p).includes('Five-star beeping'));
  p.medals[4] = 3;
  assert.ok(earned(p).includes('Five-star beeping'));
  assert.ok(!earned(p).includes('Alphabet soup'));
  const snapshot = JSON.stringify(p);
  T.achievements(p);
  assert.equal(JSON.stringify(p), snapshot);
  p.rounds = 100; p.xp = 10000; p.bestCombo = 10;
  for (let i = 0; i < 40; i++) p.medals[i] = 3;
  assert.equal(earned(p).length, 18);
  assert.deepEqual(earned(T.resetProgress(p)), []);
});

test('legacy profiles gain empty stats without losing XP, medals or audio settings', () => {
  const old = {version: 1, xp: 530, rounds: 4, bestCombo: 8, lastLesson: 3, medals: {0: 3}, settings: {wpm: 25, frequency: 825, volume: 65}};
  const migrated = T.restore(old);
  assert.equal(migrated.xp, 530);
  assert.equal(migrated.medals[0], 3);
  assert.deepEqual(migrated.settings, old.settings);
  assert.equal(T.statistics(migrated).attempts, 0);
  assert.equal(T.statistics(migrated).listeningMs, 0);
});

test('per-character stats credit the expected sound, count replays, and rank mistakes', () => {
  let p = T.newProfile();
  p = T.recordAnswer(p, 'K', 'M');
  p = T.recordAnswer(p, 'M', 'm');
  p = T.recordAnswer(p, 'M', 'K');
  p = T.recordAnswer(p, 'M', 'K');
  p = T.recordPlayback(p, 'K', T.durationMs('K', 20));
  p = T.recordPlayback(p, 'K', T.durationMs('K', 40));
  p = T.recordPlayback(p, 'M', 100); // An interrupted character.
  const stats = T.statistics(p);
  assert.equal(stats.attempts, 4);
  assert.equal(stats.correct, 1);
  assert.equal(stats.wrong, 3);
  assert.equal(stats.accuracy, 25);
  assert.equal(stats.plays, 3);
  assert.equal(stats.listeningMs, 910);
  assert.equal(stats.rows[0].character, 'M');
  assert.equal(stats.rows[0].wrong, 2);
  assert.equal(stats.rows[1].attempts, 1);
  assert.equal(stats.rows[1].plays, 2);
  assert.match(T.troubleText(stats), /^M: 2 \/ 3 missed/);
  assert.equal(T.statistics(T.restore(JSON.parse(JSON.stringify(p)))).listeningMs, 910);
  assert.equal(T.statistics(T.resetProgress(p)).attempts, 0);
});

test('listening duration sums Morse elements at each playback WPM', () => {
  assert.equal(T.durationMs('K', 20), 540);
  assert.equal(T.durationMs('K', 40), 270);
  assert.equal(T.durationMs('E', 20), 60);
  assert.equal(T.durationMs('T', 20), 180);
  assert.equal(T.durationMs('M', 20), 420);
  assert.equal(T.formatDuration(3661999), '1h 01m 01s');
  assert.equal(T.formatDuration(0), '0h 00m 00s');
  assert.equal(T.formatDuration(-1), '0h 00m 00s');
});

test('round recap is separate from global totals and does not double-count on finish', () => {
  let round = T.newRound(0, () => 0);
  let p = T.newProfile();
  while (!round.done) {
    const expected = round.queue[round.index];
    const input = round.index < 2 ? '?' : expected;
    p = T.recordAnswer(p, expected, input);
    round = T.answer(round, input);
  }
  round.listeningMs = 12345; round.plays = 13;
  const recap = T.roundStatistics(round);
  assert.equal(recap.attempts, 10);
  assert.equal(recap.correct, 8);
  assert.equal(recap.accuracy, 80);
  assert.equal(recap.plays, 13);
  assert.equal(recap.listeningMs, 12345);
  p = T.finish(p, round);
  assert.equal(T.statistics(p).attempts, 10);
  assert.equal(T.statistics(p).plays, 0);
});

test('statistics sanitize malformed counters and exclude unrecognized characters', () => {
  const p = T.restore({version: 1, stats: {characters: {
    K: {attempts: 2, correct: 99, plays: -1, listeningMs: NaN},
    Z: {attempts: -7, correct: 2, listeningMs: -42},
    nope: {attempts: 900}, M: null
  }}});
  const stats = T.statistics(p);
  assert.equal(stats.attempts, 2);
  assert.equal(stats.correct, 2);
  assert.equal(stats.listeningMs, 0);
  assert.equal(stats.plays, 0);
  assert.throws(() => T.recordAnswer(p, 'GJ', 'G'));
  assert.throws(() => T.recordPlayback(p, '☃', 500));
  assert.equal(T.statistics(T.recordPlayback(p, 'K', 0)).plays, 0);
  assert.equal(T.roundStatistics(null).attempts, 0);
});

test('statistics survive atomic state writes and reloads', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cw-stats-test-'));
  const env = {...process.env, XDG_STATE_HOME: directory};
  try {
    let p = T.recordAnswer(T.newProfile(), 'K', 'M');
    p = T.recordPlayback(p, 'K', 540);
    const write = spawnSync(process.execPath, ['helpers/state.cjs', 'write'], {env, input: JSON.stringify(p), encoding: 'utf8'});
    assert.equal(write.status, 0, write.stderr);
    const read = spawnSync(process.execPath, ['helpers/state.cjs', 'read'], {env, encoding: 'utf8'});
    assert.equal(read.status, 0, read.stderr);
    const stats = T.statistics(JSON.parse(read.stdout));
    assert.equal(stats.attempts, 1);
    assert.equal(stats.wrong, 1);
    assert.equal(stats.plays, 1);
    assert.equal(stats.listeningMs, 540);
  } finally { fs.rmSync(directory, {recursive: true, force: true}); }
});
