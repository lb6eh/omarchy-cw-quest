// Shared by QML and Node. No browser globals or third-party dependencies.
var ORDER = 'KMURESNAPTLWI.JZ=FOY,VG5/Q92H38B?47C1D60X';
var MORSE = {
  A: '.-', B: '-...', C: '-.-.', D: '-..', E: '.', F: '..-.', G: '--.',
  H: '....', I: '..', J: '.---', K: '-.-', L: '.-..', M: '--', N: '-.',
  O: '---', P: '.--.', Q: '--.-', R: '.-.', S: '...', T: '-', U: '..-',
  V: '...-', W: '.--', X: '-..-', Y: '-.--', Z: '--..',
  '0': '-----', '1': '.----', '2': '..---', '3': '...--', '4': '....-',
  '5': '.....', '6': '-....', '7': '--...', '8': '---..', '9': '----.',
  '.': '.-.-.-', ',': '--..--', '?': '..--..', '/': '-..-.', '=': '-...-'
};
function clamp(value, low, high, fallback) {
  return typeof value === 'number' && isFinite(value) ? Math.min(high, Math.max(low, Math.round(value))) : fallback;
}
function newProfile() {
  return {version: 1, xp: 0, rounds: 0, bestCombo: 0, lastLesson: 0,
    settings: {wpm: 20, frequency: 700, volume: 80}, medals: {}, stats: {characters: {}}};
}
function restore(raw) {
  var p = newProfile();
  if (!raw || raw.version !== 1) return p;
  p.xp = clamp(raw.xp, 0, 100000000, 0);
  p.rounds = clamp(raw.rounds, 0, 1000000, 0);
  p.bestCombo = clamp(raw.bestCombo, 0, 10, 0);
  p.lastLesson = clamp(raw.lastLesson, 0, ORDER.length - 2, 0);
  var s = raw.settings || {};
  p.settings = {wpm: clamp(s.wpm, 5, 50, 20), frequency: clamp(s.frequency, 300, 1200, 700), volume: clamp(s.volume, 0, 100, 80)};
  for (var i = 0; i < ORDER.length - 1; i++) p.medals[i] = clamp(raw.medals && raw.medals[i], 0, 3, 0);
  var saved = raw.stats && raw.stats.characters || {};
  for (var j = 0; j < ORDER.length; j++) {
    var ch = ORDER[j], row = saved[ch];
    if (!row || typeof row !== 'object') continue;
    var attempts = clamp(row.attempts, 0, 100000000, 0);
    p.stats.characters[ch] = {
      attempts: attempts, correct: clamp(row.correct, 0, attempts, 0),
      plays: clamp(row.plays, 0, 100000000, 0),
      listeningMs: clamp(row.listeningMs, 0, 1000000000000, 0)
    };
  }
  return p;
}
function resetProgress(profile) {
  var fresh = newProfile();
  fresh.settings = restore(profile).settings;
  return fresh;
}
function achievements(profile) {
  var p = restore(profile), bronze = 0, silver = 0, gold = 0;
  for (var i = 0; i < ORDER.length - 1; i++) {
    if (p.medals[i] >= 1) bronze++;
    if (p.medals[i] >= 2) silver++;
    if (p.medals[i] >= 3) gold++;
  }
  return [
    {name: 'First contact', detail: 'Complete your first quest', earned: p.rounds >= 1},
    {name: 'On the air', detail: 'Complete 10 quests', earned: p.rounds >= 10},
    {name: 'Perfect copy', detail: 'Answer 10 characters correctly in a row', earned: p.bestCombo >= 10},
    {name: 'Signal hunter', detail: 'Earn 1,000 XP', earned: p.xp >= 1000},
    {name: 'Participation antenna', detail: 'Earn your first bronze medal or better', earned: bronze >= 1},
    {name: 'K, thanks. M, bye.', detail: 'Earn silver or gold in lesson 1', earned: p.medals[0] >= 2},
    {name: 'Morse before chores', detail: 'Complete 25 quests. The dishes can wait.', earned: p.rounds >= 25},
    {name: 'Just one more beep', detail: 'Complete 50 quests. You said that 49 ago.', earned: p.rounds >= 50},
    {name: 'Local woodpecker', detail: 'Complete 100 quests. The trees are suspicious.', earned: p.rounds >= 100},
    {name: 'Alphabet soup', detail: 'Earn a medal in 10 different lessons', earned: bronze >= 10},
    {name: 'Beep collector', detail: 'Earn a medal in 20 different lessons', earned: bronze >= 20},
    {name: 'All your beeps belong to us', detail: 'Earn a medal in all 40 lessons', earned: bronze >= 40},
    {name: 'Five-star beeping', detail: 'Earn gold in 5 different lessons', earned: gold >= 5},
    {name: 'Gold digger, radio edition', detail: 'Earn gold in 10 different lessons', earned: gold >= 10},
    {name: 'Licensed to beep', detail: 'Earn silver or gold in all 40 lessons', earned: silver >= 40},
    {name: 'The final beep', detail: 'Earn a medal in lesson 40. Roll credits.', earned: p.medals[39] >= 1},
    {name: 'Pocket telegraph', detail: 'Earn 2,500 XP. Victorian texting unlocked.', earned: p.xp >= 2500},
    {name: 'Human modem', detail: 'Earn 10,000 XP. Please stop making dial-up noises.', earned: p.xp >= 10000}
  ];
}
function characters(lesson) { return ORDER.slice(0, clamp(lesson, 0, ORDER.length - 2, 0) + 2); }
function newRound(lesson, random) {
  var chars = characters(lesson), queue = [], rng = random || Math.random;
  // Each round introduces the newest sound, then mixes all learned characters.
  queue.push(chars.charAt(chars.length - 1));
  for (var i = 1; i < 10; i++) queue.push(chars.charAt(Math.min(chars.length - 1, Math.floor(rng() * chars.length))));
  return {lesson: lesson, queue: queue, index: 0, correct: 0, combo: 0, bestCombo: 0, xp: 0, answers: [], listeningMs: 0, plays: 0, done: false};
}
function answer(round, input) {
  var r = JSON.parse(JSON.stringify(round));
  if (r.done) return r;
  var expected = r.queue[r.index], good = String(input).toUpperCase() === expected;
  r.combo = good ? r.combo + 1 : 0;
  r.bestCombo = Math.max(r.bestCombo, r.combo);
  if (good) { r.correct++; r.xp += 10 + Math.min(10, (r.combo - 1) * 2); }
  r.answers.push({expected: expected, input: input, correct: good});
  r.index++; r.done = r.index === r.queue.length;
  return r;
}
function medal(correct) { return correct === 10 ? 3 : correct >= 9 ? 2 : correct >= 7 ? 1 : 0; }
function finish(profile, round) {
  if (!round.done) throw new Error('Cannot reward an unfinished round');
  var p = restore(profile);
  p.xp += round.xp + (round.correct >= 9 ? 30 : 0);
  p.rounds++; p.bestCombo = Math.max(p.bestCombo, round.bestCombo);
  p.lastLesson = round.lesson;
  p.medals[round.lesson] = Math.max(p.medals[round.lesson] || 0, medal(round.correct));
  return p;
}
function toneSegments(character, wpm) {
  var code = MORSE[String(character).toUpperCase()];
  if (!code) throw new Error('Unsupported Morse character');
  var unit = 1.2 / clamp(wpm, 5, 50, 20), segments = [];
  for (var i = 0; i < code.length; i++) {
    if (i) segments.push({tone: false, seconds: unit});
    segments.push({tone: true, seconds: unit * (code[i] === '.' ? 1 : 3)});
  }
  return segments;
}
function sequenceSegments(text, wpm) {
  var value = String(text).toUpperCase();
  if (!value.length || value.length > 16) throw new Error('Use 1–16 Morse characters');
  var segments = [], unit = 1.2 / clamp(wpm, 5, 50, 20);
  for (var i = 0; i < value.length; i++) {
    if (i) segments.push({tone: false, seconds: 3 * unit});
    segments = segments.concat(toneSegments(value[i], wpm));
  }
  return segments;
}
function emptyCharacterStats() {
  return {attempts: 0, correct: 0, plays: 0, listeningMs: 0};
}
function recordAnswer(profile, expected, input) {
  if (!MORSE[expected] || expected.length !== 1) throw new Error('Invalid expected character');
  var p = restore(profile), row = p.stats.characters[expected] || emptyCharacterStats();
  row.attempts++;
  if (String(input).toUpperCase() === expected) row.correct++;
  p.stats.characters[expected] = row;
  return p;
}
function durationMs(character, wpm) {
  return Math.round(toneSegments(character, wpm).reduce(function(sum, part) { return sum + part.seconds * 1000; }, 0));
}
function recordPlayback(profile, character, milliseconds) {
  if (!MORSE[character] || character.length !== 1) throw new Error('Invalid playback character');
  var p = restore(profile), ms = clamp(milliseconds, 0, 60000, 0);
  if (!ms) return p;
  var row = p.stats.characters[character] || emptyCharacterStats();
  row.plays++; row.listeningMs += ms;
  p.stats.characters[character] = row;
  return p;
}
function statistics(profile) {
  var p = restore(profile), rows = [], total = {attempts: 0, correct: 0, wrong: 0, plays: 0, listeningMs: 0};
  for (var i = 0; i < ORDER.length; i++) {
    var ch = ORDER[i], r = p.stats.characters[ch];
    if (!r || (!r.attempts && !r.plays)) continue;
    var row = {character: ch, attempts: r.attempts, correct: r.correct, wrong: r.attempts - r.correct,
      plays: r.plays, listeningMs: r.listeningMs, accuracy: r.attempts ? Math.round(100 * r.correct / r.attempts) : null};
    rows.push(row);
    total.attempts += row.attempts; total.correct += row.correct; total.wrong += row.wrong;
    total.plays += row.plays; total.listeningMs += row.listeningMs;
  }
  rows.sort(function(a, b) {
    return b.wrong - a.wrong || (a.accuracy === null ? 101 : a.accuracy) - (b.accuracy === null ? 101 : b.accuracy) || a.character.localeCompare(b.character);
  });
  total.accuracy = total.attempts ? Math.round(100 * total.correct / total.attempts) : null;
  total.rows = rows;
  return total;
}
function roundStatistics(round) {
  var p = newProfile();
  if (!round) return statistics(p);
  for (var i = 0; i < round.answers.length; i++) {
    var a = round.answers[i];
    p = recordAnswer(p, a.expected, a.input);
  }
  var result = statistics(p);
  result.listeningMs = round.listeningMs || 0;
  result.plays = round.plays || 0;
  return result;
}
function formatDuration(milliseconds) {
  var seconds = Math.floor(Math.max(0, Number(milliseconds) || 0) / 1000);
  return Math.floor(seconds / 3600) + 'h ' + String(Math.floor(seconds / 60) % 60).padStart(2, '0') + 'm ' + String(seconds % 60).padStart(2, '0') + 's';
}
function troubleText(stats) {
  var missed = stats.rows.filter(function(row) { return row.wrong > 0; });
  if (!missed.length) return stats.attempts ? 'No missed sounds. Nice copy!' : 'Answer some sounds to find your tricky letters.';
  return missed.slice(0, 3).map(function(row) { return row.character + ': ' + row.wrong + ' / ' + row.attempts + ' missed'; }).join(' · ');
}
if (typeof module !== 'undefined') module.exports = {ORDER, MORSE, newProfile, restore, characters, newRound, answer, medal, finish, toneSegments, sequenceSegments, resetProgress, achievements, recordAnswer, recordPlayback, durationMs, statistics, roundStatistics, formatDuration, troubleText};
