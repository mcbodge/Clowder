import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { frontmatter, convertAgent, convertRule, parseJsonc, mergeMcp, install, atomicWrite, optionalAgents, profilePaths, expandHome, notesExclusion, safeDestination } from './install-support.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const fixtures = fs.mkdtempSync(path.join(repo, '.installer-fixtures-'));
test.after(() => fs.rmSync(fixtures, { recursive: true, force: true }));
let sequence = 0;
function fixture() {
  const root = path.join(fixtures, `${++sequence} space ü`);
  const home = path.join(root, 'home'); const project = path.join(root, 'project');
  fs.mkdirSync(home, { recursive: true }); fs.mkdirSync(project);
  return { root, home, project };
}
function write(file, content) { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, content); }
const read = file => fs.readFileSync(file, 'utf8');
const source = (extra = '', body = 'Body') => `---\nname: 'A: # name'\ndescription: "A \\"quoted\\" description"\ntools: ['read', 'vscode/askQuestions']\n${extra}---\n${body}`;
const noDnx = { checkDnx: () => {} };
const cache = path.join(fixtures, 'cache');

test('controlled frontmatter supports scalar forms and discarded nested metadata', () => {
  const text = source("disable-model-invocation: true\nhooks:\n  name: ignored\n  nested:\n    tools: ignored\nhandoffs:\n  - label: ignored\n");
  const result = frontmatter(text, 'fixture');
  assert.equal(result.data.name, 'A: # name');
  assert.equal(result.data.description, 'A "quoted" description');
  assert.equal(result.data['disable-model-invocation'], true);
  assert.deepEqual(result.data.tools, ['read', 'vscode/askQuestions']);
  assert.equal(frontmatter(source("target: vscode\n")).data.target, undefined);
  assert.equal(frontmatter(source().replace("'A: # name'", "'Bob''s agent'")).data.name, "Bob's agent");
});
test('frontmatter rejects unsupported retained syntax, aliases, duplicates and malformed input', () => {
  for (const text of [
    source('name: duplicate\n'), source('description: |\n  multiline\n'), source('tools: [read]\n'),
    source('disable-model-invocation: "true"\n'), source('applyTo: &alias\n'),
    source().replace("name: 'A: # name'", 'name: *alias'),
    source().replace("name: 'A: # name'", 'name: !tag value'),
    source().replace("name: 'A: # name'", 'name: "unterminated'),
    source().replace("name: 'A: # name'", 'name: [invalid]'),
    source().replace("name: 'A: # name'", 'name: value # ambiguous'),
    source().replace('---\nBody', '--\nBody')
  ]) assert.throws(() => frontmatter(text, 'bad-file'), /bad-file:/);
});
test('every actual source converts with independently expected schema and eligibility', () => {
  for (const name of fs.readdirSync(path.join(repo, 'agents'))) {
    const text = read(path.join(repo, 'agents', name));
    const converted = convertAgent(text, name);
    const fm = converted.split('---')[1];
    assert.match(fm, /mainAgent: true/);
    const restricted = /^disable-model-invocation: true$/m.test(text);
    assert.match(fm, new RegExp(`subagent: ${!restricted}`));
    for (const key of ['target:', 'agents:', 'handoffs:', 'hooks:', 'disable-model-invocation:']) assert.ok(!fm.includes(key), `${name}: ${key}`);
    assert.doesNotMatch(converted, /#tool:vscode\/|\/memories\/|\bExplore\b/);
    if (/cat-(planner|auditor)/.test(name)) {
      assert.match(converted, /ask_question/);
      assert.match(converted, /write_to_file, replace_file_content and multi_replace_file_content are forbidden on any resolved path outside docs\/plans\/\*\*/);
      assert.match(converted, /No terminal writes, alternative tools, traversal or symlink escapes/);
    }
  }
  for (const value of ['true', 'false', undefined]) {
    const converted = convertAgent(source(value ? `disable-model-invocation: ${value}\n` : ''), 'fixture');
    assert.match(converted, new RegExp(`subagent: ${value !== 'true'}`));
    assert.match(converted, /name: "A: # name"/);
    assert.match(converted, /tools: \["view_file","list_dir","ask_question"\]/);
  }
  assert.throws(() => convertAgent(source().replace("'read'", "'unknown/tool'"), 'future'), /unsupported tool/);
  assert.throws(() => convertAgent(source('', '#tool:unknown/tool'), 'future'), /unsupported executable tool/);
  for (const name of fs.readdirSync(path.join(repo, 'instructions'))) {
    const text = read(path.join(repo, 'instructions', name));
    const converted = convertRule(text, name);
    const expected = /^applyTo: ['"](.+)['"]$/m.exec(text)[1];
    assert.ok(converted.includes(`globs: ${JSON.stringify(expected)}`));
    assert.match(converted, /trigger: glob/);
    assert.doesNotMatch(converted, /applyTo:/);
  }
});
test('JSONC scanner preserves strings that resemble comments, escapes and trailing commas', () => {
  const value = { url: 'https://example.test/a', content: '/* */ ,] ,} " \\', servers: {} };
  const text = '// comment\r\n' + JSON.stringify(value, null, 2).replace(/\n/g, '\r\n').replace(/}\s*$/, ', /* tail */ }\r\n');
  assert.deepEqual(JSON.parse(JSON.stringify(parseJsonc(text).value)), value);
  for (const bad of ['/*', '{"x":"bad}', '{"x":0 "y":1}', '{"x":}', '{"x":NaN}', '{} garbage', '{"x":1,,}', '[1 2]', '{"x":01}', '{"x":"\n"}']) {
    assert.throws(() => parseJsonc(bad), undefined, bad);
  }
});
test('existing MCP no version and equal version are byte-identical; explicit version touches one token', () => {
  const text = '{\r\n // keep secret-free user trivia\r\n "servers": {"mudblazor": {"command":"custom", "args":["--custom"], "env":{"OTHER":"keep", "MUDBLAZOR_VERSION": "8.0.0"}}, "other": {"url":"https://example.test/*x*/"}},\r\n "extra": [",]", ",}"],\r\n}\r\n';
  assert.equal(mergeMcp(text, 'servers', undefined, cache), text);
  assert.equal(mergeMcp(text, 'servers', '8.0.0', cache), text);
  const changed = mergeMcp(text, 'servers', '8.15.0', cache);
  assert.equal(changed, text.replace('"8.0.0"', '"8.15.0"'));
  assert.equal(mergeMcp(changed, 'servers', '8.15.0', cache), changed);
});
test('MCP insertion preserves comments/trailing commas and creates missing env', () => {
  for (const text of [
    '{}', '{ /* user */ }', '{"servers":{}}', '{"servers":{"other":{} /* after */}}',
    '{"servers":{"other":{}, // trailing\n}}', '{"servers":{"mudblazor":{}}}',
    '{"servers":{"mudblazor":{"command":"custom","env":{ /* inside */ }}}}',
    '{"servers":{"mudblazor":{"env":{"OTHER":"keep", /* after comma */ }}}}'
  ]) {
    const changed = mergeMcp(text, 'servers', '8.15.0', cache, noDnx);
    const result = parseJsonc(changed).value;
    assert.equal(result.servers.mudblazor.env.MUDBLAZOR_VERSION, '8.15.0');
    if (text.includes('/*')) assert.ok(changed.includes(text.match(/\/\*.*?\*\//)[0]));
    assert.equal(mergeMcp(changed, 'servers', '8.15.0', cache, noDnx), changed);
  }
  const result = parseJsonc(mergeMcp('{}', 'mcpServers', '8.15.0', cache, noDnx)).value.mcpServers.mudblazor;
  assert.equal(result.command, 'dnx');
  assert.deepEqual(result.args, ['MudMCP', '--yes', '--', '--stdio']);
  assert.equal(result.env.MudBlazor__Repository__DataPath, path.resolve(cache));
  assert.throws(() => mergeMcp('{}', 'servers', undefined, cache), /-MudBlazorVersion \/ --mudblazor-version/);
  assert.throws(() => mergeMcp('{}', 'servers', '8.15.0', cache, { checkDnx() { throw new Error('.NET 10 SDK and dnx'); } }), /\.NET 10 SDK and dnx/);
});
test('MCP preflight rejects invalid shapes, duplicate targets/case variants, versions and overrides', () => {
  for (const text of [
    'null', '[]', '{"servers":null}', '{"servers":[]}', '{"servers":{},"servers":{}}',
    '{"servers":{"mudblazor":null}}', '{"servers":{"mudblazor":[]}}',
    '{"servers":{"mudblazor":{},"mudblazor":{}}}', '{"servers":{"MudBlazor":{}}}',
    '{"servers":{"mudblazor":{"env":null}}}', '{"servers":{"mudblazor":{"env":[]}}}',
    '{"servers":{"mudblazor":{"env":"bad"}}}', '{"servers":{"mudblazor":{"command":0}}}',
    '{"servers":{"mudblazor":{"args":{}}}}', '{"servers":{"mudblazor":{"args":[1]}}}',
    '{"servers":{"mudblazor":{"env":{},"env":{}}}}',
    '{"servers":{"mudblazor":{"env":{"MUDBLAZOR_VERSION":"1","MUDBLAZOR_VERSION":"2"}}}}'
  ]) assert.throws(() => mergeMcp(text, 'servers', undefined, cache), undefined, text);
  for (const args of [['--version', '7'], ['--version=7']]) {
    const text = JSON.stringify({ servers: { mudblazor: { args } } });
    assert.equal(mergeMcp(text, 'servers', undefined, cache), text);
    assert.throws(() => mergeMcp(text, 'servers', '8.0.0', cache), /--version override/);
  }
  for (const version of ['', 'latest', '8', '8.0', '8.0.0\nsecret']) assert.throws(() => mergeMcp('{}', 'servers', version, cache, noDnx), /valid/);
});
test('atomic writes skip unchanged content and preserve originals on interrupted writes/replacements', () => {
  const { root } = fixture(); const file = path.join(root, 'mcp.json');
  assert.equal(atomicWrite(file, '{}'), true);
  const mtime = fs.statSync(file).mtimeMs;
  assert.equal(atomicWrite(file, '{}'), false);
  assert.equal(fs.statSync(file).mtimeMs, mtime);
  const io = { ...fs, writeFileSync(target) { fs.writeFileSync(target, 'partial'); throw new Error('interrupted'); } };
  assert.throws(() => atomicWrite(file, 'changed', io), /interrupted/);
  assert.equal(read(file), '{}');
  assert.deepEqual(fs.readdirSync(root).filter(n => n.endsWith('.tmp')), []);
  assert.throws(() => atomicWrite(file, 'changed', { ...fs, renameSync() { throw new Error('permission denied'); } }), /permission denied/);
  assert.equal(read(file), '{}');
});
test('platform profile selection and literal tilde expansion', () => {
  const { home } = fixture();
  for (const platform of ['win32', 'darwin', 'linux']) {
    const paths = profilePaths(home, platform, { APPDATA: path.join(home, 'roaming'), XDG_CONFIG_HOME: path.join(home, 'xdg') });
    assert.equal(paths.length, 2);
    assert.ok(paths.every(p => p.endsWith('User')));
    assert.ok(paths[1].includes('Code - Insiders'));
  }
  assert.throws(() => profilePaths(home, 'win32', {}), /APPDATA/);
  assert.equal(expandHome('~', home), home);
  assert.equal(expandHome('~\\custom profile\\mcp.json', home), path.join(home, 'custom profile', 'mcp.json'));
});
test('all-target config preflight fails without creating any target; explicit global exception', () => {
  const { home, project } = fixture();
  write(path.join(project, '.vscode', 'mcp.json'), '{"servers":{"mudblazor":{}}}');
  const invalid = path.join(project, '.agents', 'mcp_config.json');
  write(invalid, '{"mcpServers":null}');
  assert.throws(() => install({ repo, project, harness: 'all', mud: true }, { home, log() {} }), /mcpServers/);
  assert.ok(!fs.existsSync(path.join(project, '.agents', 'agents')));
  assert.ok(!fs.existsSync(path.join(project, '.github')));
  assert.equal(read(invalid), '{"mcpServers":null}');
  fs.unlinkSync(invalid);
  const override = path.join(home, 'custom', 'mcp.json');
  install({ repo, project, harness: 'all', globalMcp: true, version: '8.15.0', mcpPath: override }, { home, ...noDnx, log() {} });
  assert.ok(fs.existsSync(override));
  assert.ok(fs.existsSync(path.join(home, '.gemini', 'config', 'mcp_config.json')));
  assert.ok(!fs.existsSync(invalid));
  assert.equal(read(path.join(project, '.vscode', 'mcp.json')), '{"servers":{"mudblazor":{}}}');
});
test('global MCP targets only existing Stable/Insiders profiles and preserves GEMINI user content', () => {
  const { home } = fixture(); const env = { APPDATA: path.join(home, 'roaming'), XDG_CONFIG_HOME: path.join(home, 'xdg') };
  assert.throws(() => install({ repo, harness: 'copilot', globalMcp: true, version: '8.0.0' }, { home, env, ...noDnx }), /No existing/);
  const profiles = profilePaths(home, process.platform, env);
  profiles.forEach(dir => fs.mkdirSync(dir, { recursive: true }));
  write(path.join(home, '.gemini', 'GEMINI.md'), 'User instructions\n');
  const options = { repo, harness: 'all', globalMcp: true, version: '8.0.0' };
  install(options, { home, env, ...noDnx, log() {} });
  profiles.forEach(dir => assert.ok(fs.existsSync(path.join(dir, 'mcp.json'))));
  const gemini = path.join(home, '.gemini', 'GEMINI.md'); const first = read(gemini);
  install(options, { home, env, ...noDnx, log() {} });
  assert.equal(read(gemini), first);
  assert.ok(first.startsWith('User instructions\n'));
  assert.equal(first.split('<!-- clowder:start -->').length, 2);
});
test('Antigravity opt-out removes only exact owned names; unrelated files and MCP survive', () => {
  const { home, project } = fixture();
  const dir = path.join(project, '.agents', 'agents');
  for (const name of optionalAgents) { write(path.join(dir, name + '.md'), 'optional'); write(path.join(dir, name + '.agent.md'), 'legacy'); }
  write(path.join(dir, 'user-mudblazor.md'), 'keep');
  const config = path.join(project, '.agents', 'mcp_config.json'); write(config, '{"mcpServers":{"mudblazor":{}}}');
  install({ repo, harness: 'antigravity', project }, { home, log() {} });
  assert.equal(read(path.join(dir, 'user-mudblazor.md')), 'keep');
  optionalAgents.forEach(name => { assert.ok(!fs.existsSync(path.join(dir, name + '.md'))); assert.ok(!fs.existsSync(path.join(dir, name + '.agent.md'))); });
  assert.equal(read(config), '{"mcpServers":{"mudblazor":{}}}');
  assert.ok(!fs.existsSync(path.join(home, '.copilot')));
});
test('unsafe symlinked deletion/config destinations are rejected', t => {
  const { root, project, home } = fixture(); const outside = path.join(root, 'outside'); fs.mkdirSync(outside);
  const linked = path.join(project, '.agents');
  try { fs.symlinkSync(outside, linked, process.platform === 'win32' ? 'junction' : 'dir'); }
  catch (error) { t.skip(`symlink creation unavailable: ${error.code}`); return; }
  assert.throws(() => safeDestination(path.join(linked, 'agents', 'x.md')), /linked destination/);
  assert.throws(() => install({ repo, project, harness: 'antigravity' }, { home, log() {} }), /linked destination/);
  assert.deepEqual(fs.readdirSync(outside), []);
});
test('git notes exclusions resolve nested projects and linked worktrees idempotently', () => {
  const { root, project } = fixture();
  function git(args) {
    const result = spawnSync('git', args, { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim();
  }
  git(['init', '-q', project]);
  const nested = path.join(project, 'nested project'); fs.mkdirSync(nested);
  const excludeFile = path.join(project, '.git', 'info', 'exclude'); write(excludeFile, '# user excludes\n');
  for (let i = 0; i < 2; i++) {
    const exclusion = notesExclusion(nested);
    atomicWrite(exclusion.file, exclusion.content);
  }
  assert.equal(read(excludeFile), '# user excludes\n/nested\\ project/docs/plans/.clowder-notes/\n');
  write(path.join(nested, 'docs', 'plans', '.clowder-notes', 'note.md'), 'private note');
  assert.equal(git(['-C', project, 'status', '--porcelain']), '');
  git(['-C', project, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-q', '--allow-empty', '-m', 'fixture']);
  const worktree = path.join(root, 'worktree'); git(['-C', project, 'worktree', 'add', '-q', '-b', 'fixture-branch', worktree]);
  assert.ok(fs.statSync(path.join(worktree, '.git')).isFile());
  const exclusion = notesExclusion(worktree); atomicWrite(exclusion.file, exclusion.content);
  write(path.join(worktree, 'docs', 'plans', '.clowder-notes', 'note.md'), 'private');
  assert.equal(git(['-C', worktree, 'status', '--porcelain']), '');
  assert.ok(!fs.existsSync(path.join(project, '.gitignore')));
});

const bashCandidates = process.platform === 'win32' ? ['C:\\Program Files\\Git\\bin\\bash.exe'] : ['/bin/bash', '/usr/bin/bash'];
const bash = bashCandidates.find(p => fs.existsSync(p));
const powershell = process.platform === 'win32' ? path.join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe') : 'pwsh';
const psAvailable = spawnSync(powershell, ['-NoProfile', '-Command', 'exit 0']).status === 0;
const bashPath = value => process.platform === 'win32' ? value.replace(/^([A-Za-z]):/, (_, drive) => '/' + drive.toLowerCase()).replaceAll('\\', '/') : value;
function wrapperFixture() {
  const f = fixture(); const bin = path.join(f.root, 'bin'); fs.mkdirSync(bin);
  for (const name of ['git', 'npm', 'gh', 'uv', 'playwright-cli']) {
    write(path.join(bin, name), `#!/bin/sh\nprintf '%s\\n' '${name}' >> "$CLOWDER_FIXTURE_LOG"\n${name === 'git' ? '[ "$3" != rev-parse ] || exit 1\n' : ''}exit 0\n`);
    fs.chmodSync(path.join(bin, name), 0o755);
    write(path.join(bin, name + '.cmd'), `@echo ${name}>>"%CLOWDER_FIXTURE_LOG%"\r\n${name === 'git' ? '@if "%~3"=="rev-parse" exit /b 1\r\n' : ''}@exit /b 0\r\n`);
  }
  const tool = path.join(bin, 'companion.cjs');
  write(tool, `
const fs = require('node:fs'), path = require('node:path');
const [name, ...args] = process.argv.slice(2);
fs.appendFileSync(process.env.CLOWDER_FIXTURE_LOG, name + '\\n');
fs.appendFileSync(process.env.CLOWDER_FIXTURE_LOG + '.jsonl', JSON.stringify({ name, args, cwd: process.cwd() }) + '\\n');
if (process.env.CLOWDER_FAIL === name) { console.error('fixture failure: ' + name); process.exit(1); }
if (process.env.CLOWDER_EMPTY === name) process.exit(0);
const skill = name === 'gh' ? 'azure-devops-cli' : name === 'playwright-cli' ? 'playwright-cli' : null;
if (skill) {
  const base = name === 'gh' ? args[args.indexOf('--dir') + 1] : path.join(process.cwd(), '.agents', 'skills');
  const dest = path.join(base, skill); fs.mkdirSync(dest, { recursive: true });
  fs.writeFileSync(path.join(dest, 'SKILL.md'), 'upstream ' + skill);
  fs.writeFileSync(path.join(dest, 'reference.txt'), 'reference');
}
`);
  for (const name of ['npm', 'gh', 'playwright-cli']) {
    write(path.join(bin, name), `#!/bin/sh\nexec node "$(dirname "$0")/companion.cjs" ${name} "$@"\n`);
    write(path.join(bin, name + '.cmd'), `@"${process.execPath}" "%~dp0companion.cjs" ${name} %*\r\n`);
  }
  const env = { ...process.env, HOME: f.home, USERPROFILE: f.home, APPDATA: path.join(f.home, 'roaming'), XDG_CONFIG_HOME: path.join(f.home, 'xdg'), PATH: bin + path.delimiter + process.env.PATH, CLOWDER_DIR: repo, CLOWDER_FIXTURE_LOG: path.join(f.root, 'calls.log') };
  env.CLOWDER_FIXTURE_BIN = bashPath(bin);
  env.CLOWDER_FIXTURE_HOME = bashPath(f.home);
  env.CLOWDER_FIXTURE_REPO = bashPath(repo);
  env.CLOWDER_FIXTURE_BASH_LOG = bashPath(env.CLOWDER_FIXTURE_LOG);
  env.CLOWDER_FIXTURE_NODE = bashPath(path.dirname(process.execPath));
  return { ...f, env, bin };
}
function invoke(wrapper, f, args) {
  if (wrapper === 'powershell') {
    const escapedHome = f.home.replaceAll("'", "''");
    const escapedScript = path.join(repo, 'scripts', 'update-all.ps1').replaceAll("'", "''");
    return spawnSync(powershell, ['-NoProfile', '-Command', `Set-Variable HOME '${escapedHome}' -Force; & '${escapedScript}' ${args.map(a => /^-[A-Za-z]+$/.test(a) ? a : `'${a.replaceAll("'", "''")}'`).join(' ')}`], { env: f.env, encoding: 'utf8', timeout: 120000 });
  }
  return spawnSync(bash, ['-c', 'export PATH="$CLOWDER_FIXTURE_BIN:$CLOWDER_FIXTURE_NODE:/usr/bin:/bin"; export HOME="$CLOWDER_FIXTURE_HOME"; export CLOWDER_DIR="$CLOWDER_FIXTURE_REPO"; export CLOWDER_FIXTURE_LOG="$CLOWDER_FIXTURE_BASH_LOG"; exec /bin/bash "$@"', '--', bashPath(path.join(repo, 'scripts', 'update-all.sh')), ...args.map(a => /^[A-Za-z]:\\/.test(a) ? bashPath(a) : a)], { env: f.env, encoding: 'utf8', timeout: 120000 });
}
for (const wrapper of ['powershell', 'bash']) {
  const available = wrapper === 'powershell' ? psAvailable : !!bash;
  test(`${wrapper}: isolated harness x scope x Mud matrix; idempotency, companions and unselected targets`, { skip: !available }, () => {
    for (const harness of ['copilot', 'antigravity', 'all']) for (const scope of ['project', 'global']) for (const mud of [false, true]) {
      const f = wrapperFixture();
      const projectMode = scope === 'project';
      for (const name of ['.github', '.agents']) write(path.join(f.project, name, 'agents', 'user.agent.md'), 'keep');
      for (const base of [path.join(f.project, '.github'), path.join(f.project, '.agents'), path.join(f.home, '.copilot'), path.join(f.home, '.gemini', 'config')]) {
        write(path.join(base, 'skills', 'user-skill', 'SKILL.md'), 'keep');
        write(path.join(base, 'skills', 'azure-devops-cli', 'user.txt'), 'keep');
      }
      if (mud && projectMode) {
        write(path.join(f.project, '.vscode', 'mcp.json'), '{"servers":{"mudblazor":{}}}');
        write(path.join(f.project, '.agents', 'mcp_config.json'), '{"mcpServers":{"mudblazor":{}}}');
      }
      const args = wrapper === 'powershell' ? ['-Harness', harness, ...(projectMode ? ['-ProjectDir', f.project] : []), ...(mud ? ['-MudBlazor'] : [])] :
        ['--harness=' + harness, ...(projectMode ? ['--project', f.project] : []), ...(mud ? ['--mudblazor'] : [])];
      const result = invoke(wrapper, f, args);
      assert.equal(result.status, 0, `${wrapper}/${harness}/${scope}/${mud}\n${result.stdout}\n${result.stderr}`);
      for (const target of ['copilot', 'antigravity']) {
        const selected = harness === target || harness === 'all';
        const base = projectMode ? path.join(f.project, target === 'copilot' ? '.github' : '.agents') : path.join(f.home, target === 'copilot' ? '.copilot' : '.gemini/config');
        const suffix = target === 'copilot' ? '.agent.md' : '.md';
        assert.equal(fs.existsSync(path.join(base, 'agents', 'cat-planner' + suffix)), selected);
        for (const stem of optionalAgents) assert.equal(fs.existsSync(path.join(base, 'agents', stem + suffix)), selected && mud);
        for (const name of ['azure-devops-cli', 'playwright-cli']) {
          assert.equal(fs.existsSync(path.join(base, 'skills', name, 'SKILL.md')), selected);
          if (selected) {
            assert.equal(read(path.join(base, 'skills', name, 'SKILL.md')), 'upstream ' + name);
            assert.equal(read(path.join(base, 'skills', name, 'reference.txt')), 'reference');
          }
          assert.equal(read(path.join(base, 'skills', 'user-skill', 'SKILL.md')), 'keep');
          assert.equal(read(path.join(base, 'skills', 'azure-devops-cli', 'user.txt')), 'keep');
        }
        if (projectMode) assert.equal(read(path.join(base, 'agents', 'user.agent.md')), 'keep');
      }
      const calls = read(f.env.CLOWDER_FIXTURE_LOG).trim().split(/\r?\n/);
      assert.equal(calls.filter(c => c === 'uv').length, projectMode ? 0 : 1);
      for (const name of ['npm', 'gh', 'playwright-cli']) assert.equal(calls.filter(c => c === name).length, 1);
      const details = read(f.env.CLOWDER_FIXTURE_LOG + '.jsonl').trim().split(/\r?\n/).map(JSON.parse);
      assert.deepEqual(details.find(c => c.name === 'npm').args, ['install', '-g', '@playwright/cli@latest']);
      assert.deepEqual(details.find(c => c.name === 'playwright-cli').args, ['install', '--skills', 'agents']);
      const ghCall = details.find(c => c.name === 'gh');
      assert.deepEqual(ghCall.args.slice(0, 4), ['skill', 'install', 'github/awesome-copilot', 'azure-devops-cli']);
      assert.equal(ghCall.args[4], '--dir');
      assert.equal(ghCall.args[6], '--force');
      assert.equal(path.resolve(ghCall.args[5]), path.join(ghCall.cwd, '.agents', 'skills'));
      assert.equal(ghCall.cwd, details.find(c => c.name === 'playwright-cli').cwd);
      assert.match(path.basename(ghCall.cwd), /^\.clowder-companions-/);
      assert.ok(!fs.existsSync(ghCall.cwd));
      const repeat = invoke(wrapper, f, args);
      assert.equal(repeat.status, 0, repeat.stderr);
      assert.ok(!fs.existsSync(path.join(f.home, '.gemini', 'config', 'hooks')));
    }
  });
  test(`${wrapper}: companion failures and absent output warn without blocking Clowder`, { skip: !available }, () => {
    for (const mode of ['CLOWDER_FAIL', 'CLOWDER_EMPTY']) for (const name of ['npm', 'gh', 'playwright-cli']) {
      const f = wrapperFixture(); f.env[mode] = name;
      const oldSkill = path.join(f.project, '.github', 'skills', 'azure-devops-cli', 'SKILL.md');
      write(oldSkill, 'placeholder, not an upstream skill');
      const result = invoke(wrapper, f, wrapper === 'powershell' ? ['-ProjectDir', f.project] : ['--project', f.project]);
      assert.equal(result.status, 0, result.stdout + result.stderr);
      assert.ok(fs.existsSync(path.join(f.project, '.github', 'agents', 'cat-planner.agent.md')));
      if (!(mode === 'CLOWDER_EMPTY' && name === 'npm')) assert.match(result.stdout + result.stderr, /WARNING|WARNING:/i);
      if (name === 'gh') {
        assert.match(result.stdout + result.stderr, mode === 'CLOWDER_FAIL' ? /Install\/upgrade GitHub CLI/ : /NOT installed\/updated/);
        assert.equal(read(oldSkill), 'placeholder, not an upstream skill');
        assert.doesNotMatch(result.stdout, /Installed companion skill: .*azure-devops-cli/);
      }
    }
  });
  test(`${wrapper}: relative project placement survives isolated staging cwd`, { skip: !available }, () => {
    const f = wrapperFixture();
    const relative = path.relative(repo, f.project);
    const result = invoke(wrapper, f, wrapper === 'powershell' ? ['-ProjectDir', relative] : ['--project', bashPath(relative).replaceAll('\\', '/')]);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    for (const name of ['playwright-cli', 'azure-devops-cli']) assert.equal(read(path.join(f.project, '.github', 'skills', name, 'SKILL.md')), 'upstream ' + name);
  });
  test(`${wrapper}: invalid options fail before git or writes`, { skip: !available }, () => {
    for (const args of (wrapper === 'powershell' ? [
      ['-Harness', 'invalid'], ['-Harness'], ['-Unknown'], ['-MudBlazorVersion', '8.0.0'],
      ['-CopilotMcpPath', 'profile.json'], ['-ProjectDir', 'missing'], ['-ProjectDir', ''], ['-CopilotMcpPath', '']
    ] : [
      ['--harness=invalid'], ['--harness'], ['--unknown'], ['--project='], ['--project'],
      ['--mudblazor-version', '8.0.0'], ['--copilot-mcp-path', 'profile.json'], ['--project', 'missing'], ['--project', ''], ['--copilot-mcp-path', '']
    ])) {
      const f = wrapperFixture(); const result = invoke(wrapper, f, args);
      assert.notEqual(result.status, 0, `${wrapper}: ${args}`);
      assert.ok(!fs.existsSync(f.env.CLOWDER_FIXTURE_LOG), `${wrapper}: validation ran git`);
      assert.ok(!fs.existsSync(path.join(f.home, '.copilot')));
    }
  });
  test(`${wrapper}: new MCP missing version fails before target copies and preserves original`, { skip: !available }, () => {
    const f = wrapperFixture(); const config = path.join(f.project, '.vscode', 'mcp.json'); write(config, '{ /* keep */ "servers":{} }');
    const args = wrapper === 'powershell' ? ['-ProjectDir', f.project, '-MudBlazor'] : ['--project', f.project, '--mudblazor'];
    const result = invoke(wrapper, f, args);
    assert.notEqual(result.status, 0);
    assert.match(result.stdout + result.stderr, /MudBlazorVersion|mudblazor-version/);
    assert.equal(read(config), '{ /* keep */ "servers":{} }');
    assert.ok(!fs.existsSync(path.join(f.project, '.github')));
  });
  test(`${wrapper}: core needs no Node, conversion fails early without Node`, { skip: !available }, t => {
    const f = wrapperFixture();
    for (const name of ['npm', 'gh', 'playwright-cli']) for (const suffix of ['', '.cmd']) fs.rmSync(path.join(f.bin, name + suffix));
    // Controlled PATH keeps shells/system utilities and fake git, but no Node/package managers.
    if (wrapper === 'powershell') {
      f.env.PATH = f.bin + path.delimiter + path.join(process.env.SystemRoot || '/usr', 'System32');
    } else {
      f.env.CLOWDER_FIXTURE_NODE = '';
      if (process.platform !== 'win32' && fs.existsSync('/usr/bin/node')) { t.skip('This platform puts Node beside required shell utilities; absence fixture is Windows-specific.'); return; }
    }
    const homeProject = path.join(f.home, 'project space'); fs.mkdirSync(homeProject);
    const projectArgs = wrapper === 'powershell' ? ['-ProjectDir', '~\\project space'] : ['--project', '~/project space'];
    const success = invoke(wrapper, f, projectArgs);
    assert.equal(success.status, 0, success.stderr);
    assert.ok(fs.existsSync(path.join(homeProject, '.github', 'agents', 'cat-planner.agent.md')));
    assert.match(success.stdout + success.stderr, /npm not found/);
    assert.match(success.stdout + success.stderr, /GitHub CLI \(gh\) not found/);
    assert.match(success.stdout + success.stderr, /playwright-cli not found/);
    const failure = invoke(wrapper, f, [...projectArgs, ...(wrapper === 'powershell' ? ['-Harness', 'antigravity'] : ['--harness', 'antigravity'])]);
    assert.notEqual(failure.status, 0);
    assert.match(failure.stdout + failure.stderr, /Node.js 22\+/);
    assert.ok(!fs.existsSync(path.join(homeProject, '.agents')));
    assert.equal(read(f.env.CLOWDER_FIXTURE_LOG).trim().split(/\r?\n/).length, 1);
  });
  test(`${wrapper}: off-on-off transition preserves existing MCP and unrelated content`, { skip: !available }, () => {
    const f = wrapperFixture();
    const copilotMcp = path.join(f.project, '.vscode', 'mcp.json');
    const antigravityMcp = path.join(f.project, '.agents', 'mcp_config.json');
    write(copilotMcp, '{"servers":{"mudblazor":{"command":"custom"}}}');
    write(antigravityMcp, '{"mcpServers":{"mudblazor":{"command":"custom"}}}');
    for (const dir of ['.github', '.agents']) write(path.join(f.project, dir, 'agents', 'user-mudblazor.md'), 'keep');
    const args = wrapper === 'powershell' ? ['-ProjectDir', f.project, '-Harness', 'all'] : ['--project', f.project, '--harness', 'all'];
    for (const mud of [false, true, false]) {
      const result = invoke(wrapper, f, [...args, ...(mud ? [wrapper === 'powershell' ? '-MudBlazor' : '--mudblazor'] : [])]);
      assert.equal(result.status, 0, result.stderr);
      for (const dir of ['.github', '.agents']) {
        const suffix = dir === '.github' ? '.agent.md' : '.md';
        optionalAgents.forEach(stem => assert.equal(fs.existsSync(path.join(f.project, dir, 'agents', stem + suffix)), mud));
        assert.equal(read(path.join(f.project, dir, 'agents', 'user-mudblazor.md')), 'keep');
      }
    }
    assert.equal(read(copilotMcp), '{"servers":{"mudblazor":{"command":"custom"}}}');
    assert.equal(read(antigravityMcp), '{"mcpServers":{"mudblazor":{"command":"custom"}}}');
    assert.ok(!fs.existsSync(path.join(f.home, '.copilot')));
  });
  test(`${wrapper}: global MCP implies Mud alongside the npm project-mode global exception`, { skip: !available }, () => {
    const f = wrapperFixture();
    const config = path.join(f.home, 'custom profile', 'mcp.json');
    const anti = path.join(f.home, '.gemini', 'config', 'mcp_config.json');
    const entry = '{"command":"custom","env":{"MUDBLAZOR_VERSION":"8.0.0","OTHER":"keep"}}';
    const original = `{ /* user */ "servers":{"mudblazor":${entry}} }`;
    const antiOriginal = `{"mcpServers":{"mudblazor":${entry}}}`;
    write(config, original); write(anti, antiOriginal);
    const args = wrapper === 'powershell' ?
      ['-ProjectDir', f.project, '-Harness', 'all', '-GlobalMudMcp', '-MudBlazorVersion', '8.15.0', '-CopilotMcpPath', '~\\custom profile\\mcp.json'] :
      ['--project', f.project, '--harness', 'all', '--global-mud-mcp', '--mudblazor-version=8.15.0', '--copilot-mcp-path', '~/custom profile/mcp.json'];
    const result = invoke(wrapper, f, args);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Explicit GlobalMudMcp exception/);
    assert.equal(read(config), original.replace('"8.0.0"', '"8.15.0"'));
    assert.equal(read(anti), antiOriginal.replace('"8.0.0"', '"8.15.0"'));
    assert.ok(!fs.existsSync(path.join(f.project, '.vscode', 'mcp.json')));
    assert.ok(!fs.existsSync(path.join(f.project, '.agents', 'mcp_config.json')));
    assert.ok(!fs.existsSync(path.join(f.home, '.copilot')));
    assert.ok(!fs.existsSync(path.join(f.home, '.gemini', 'config', 'agents')));
    for (const stem of optionalAgents) {
      assert.ok(fs.existsSync(path.join(f.project, '.github', 'agents', stem + '.agent.md')));
      assert.ok(fs.existsSync(path.join(f.project, '.agents', 'agents', stem + '.md')));
    }
    const calls = read(f.env.CLOWDER_FIXTURE_LOG).trim().split(/\r?\n/);
    for (const name of ['npm', 'gh', 'playwright-cli']) assert.equal(calls.filter(c => c === name).length, 1);
    assert.ok(!calls.includes('uv'));
  });
}
test('repository-owned optional skill convention excludes only source-owned bundles and preserves binary bytes', () => {
  const { root, home, project } = fixture();
  const synthetic = path.join(root, 'source');
  for (const directory of ['agents', 'instructions', 'skills']) fs.cpSync(path.join(repo, directory), path.join(synthetic, directory), { recursive: true });
  const binary = Buffer.from([0, 255, 127, 128, 9]);
  write(path.join(synthetic, 'skills', 'cat-mudblazor-fixture', 'SKILL.md'), 'optional fixture');
  write(path.join(synthetic, 'skills', 'cat-mudblazor-fixture', 'asset.bin'), binary);
  const base = path.join(project, '.agents', 'skills');
  write(path.join(base, 'cat-mudblazor-user', 'SKILL.md'), 'not source owned');
  write(path.join(project, '.agents', 'mcp_config.json'), '{"mcpServers":{"mudblazor":{}}}');
  const options = { repo: synthetic, project, harness: 'antigravity' };
  install({ ...options, mud: true }, { home, log() {} });
  assert.deepEqual(fs.readFileSync(path.join(base, 'cat-mudblazor-fixture', 'asset.bin')), binary);
  install(options, { home, log() {} });
  assert.ok(!fs.existsSync(path.join(base, 'cat-mudblazor-fixture')));
  assert.equal(read(path.join(base, 'cat-mudblazor-user', 'SKILL.md')), 'not source owned');
});
test('all-target preflight refuses directory-shaped and symlinked native Copilot targets before Antigravity writes', () => {
  const { home, project } = fixture();
  const invalid = path.join(project, '.github', 'agents', 'cat-planner.agent.md'); fs.mkdirSync(invalid, { recursive: true });
  assert.throws(() => install({ repo, home, project, harness: 'all' }, { home, log() {} }), /Expected file/);
  assert.ok(!fs.existsSync(path.join(project, '.agents')));
});
test('five source planners share the identical clarification gate and no legacy batching contradiction', () => {
  let gate;
  for (const name of ['cat-planner', 'cat-planner-mudblazor', 'cat-planner-devops', 'cat-planner-devops-mudblazor', 'cat-auditor']) {
    const text = read(path.join(repo, 'agents', name + '.agent.md'));
    const current = /^<clarification_gate>\r?\n([\s\S]*?)^<\/clarification_gate>/m.exec(text)?.[1].replaceAll('\r', '');
    assert.ok(current);
    if (!gate) gate = current; else assert.equal(current, gate);
    assert.match(current, /discovery pass first/);
    assert.match(current, /immediately invoke/);
    assert.match(current, /one call batching independent/);
    assert.match(current, /no equivalent native interactive tool genuinely exists/);
    assert.match(current, /<=3 blocking questions/);
    assert.doesNotMatch(text, /batch at most 3|Ask questions only via|Intent-only questions .*go straight to the user/);
  }
});
test('helper has only built-in dependencies and no package manager execution', () => {
  const code = read(path.join(repo, 'scripts', 'install-support.mjs'));
  for (const match of code.matchAll(/from ['"]([^'"]+)['"]/g)) assert.ok(match[1].startsWith('node:'));
  assert.doesNotMatch(code, /spawnSync\(['"](?:npm|npx|curl|wget)/);
});
test('helper subprocess succeeds with no npm or companion executables on PATH', () => {
  const { root, home, project } = fixture();
  const bin = path.join(root, 'empty-bin'); fs.mkdirSync(bin);
  const result = spawnSync(process.execPath, [path.join(repo, 'scripts', 'install-support.mjs'), 'repo', repo, 'harness', 'antigravity', 'project', project], {
    env: { ...process.env, HOME: home, USERPROFILE: home, PATH: bin }, encoding: 'utf8', timeout: 30000
  });
  assert.equal(result.status, 0, result.stderr);
  assert.ok(fs.existsSync(path.join(project, '.agents', 'agents', 'cat-planner.md')));
  assert.ok(!fs.existsSync(path.join(home, '.copilot')));
});
test('missing SDK/dnx fails helper preflight before target writes without exposing config contents', () => {
  const { root, home, project } = fixture(); const bin = path.join(root, 'empty-bin'); fs.mkdirSync(bin);
  const config = path.join(project, '.agents', 'mcp_config.json');
  const original = '{"mcpServers":{"unrelated":{"env":{"TOKEN":"fixture-do-not-log"}}}}';
  write(config, original);
  const result = spawnSync(process.execPath, [path.join(repo, 'scripts', 'install-support.mjs'), 'repo', repo, 'harness', 'antigravity', 'project', project, 'mud', 'true', 'version', '8.15.0'], {
    env: { ...process.env, HOME: home, USERPROFILE: home, PATH: bin }, encoding: 'utf8', timeout: 30000
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /\.NET 10 SDK.*dnx/);
  assert.doesNotMatch(result.stdout + result.stderr, /fixture-do-not-log/);
  assert.equal(read(config), original);
  assert.ok(!fs.existsSync(path.join(project, '.agents', 'agents')));
});
