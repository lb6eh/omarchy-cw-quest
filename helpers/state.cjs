const fs = require('node:fs');
const path = require('node:path');
const { restore } = require('../Trainer.js');
const base = process.env.XDG_STATE_HOME;
const directory = path.join(base && path.isAbsolute(base) ? base : path.join(process.env.HOME, '.local/state'), 'omarchy-cw-quest');
const file = path.join(directory, 'profile.json');
try {
  if (process.argv[2] === 'read') {
    if (!fs.existsSync(file)) process.stdout.write(JSON.stringify(restore(null)));
    else {
      const stat = fs.lstatSync(file);
      if (!stat.isFile() || stat.size > 65536) throw new Error('Invalid profile file');
      process.stdout.write(JSON.stringify(restore(JSON.parse(fs.readFileSync(file, 'utf8')))));
    }
  } else if (process.argv[2] === 'write') {
    let input = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', chunk => { input += chunk; if (input.length > 65536) process.exit(2); });
    process.stdin.on('end', () => {
      try {
        const profile = restore(JSON.parse(input));
        fs.mkdirSync(directory, {recursive: true, mode: 0o700});
        const temp = path.join(directory, `.profile-${process.pid}.tmp`);
        fs.writeFileSync(temp, JSON.stringify(profile), {mode: 0o600, flag: 'wx'});
        fs.renameSync(temp, file);
      } catch (error) { console.error(error.message); process.exitCode = 1; }
    });
  } else process.exit(2);
} catch (error) { console.error(error.message); process.exitCode = 1; }
