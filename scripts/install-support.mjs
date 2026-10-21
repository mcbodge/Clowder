import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const optionalAgents = ['cat-mudblazor-engineer', 'cat-planner-mudblazor', 'cat-planner-devops-mudblazor', 'cat-plan-executor-mudblazor'];
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const quote = value => JSON.stringify(value);

// This reader intentionally accepts only the frontmatter forms maintained in this repository.
export function frontmatter(text, file = '<input>') {
  const fail = message => { throw new Error(`${file}: ${message}`); };
  const match = /^\uFEFF?---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(text);
  if (!match) fail('missing or malformed frontmatter');
  const retained = new Set(['name', 'description', 'tools', 'applyTo', 'disable-model-invocation']);
  const discarded = new Set(['argument-hint', 'target', 'agents', 'handoffs', 'hooks', 'model', 'user-invocable']);
  function scalar(raw) {
    raw = raw.trim();
    if (raw.startsWith("'")) {
      if (!/^'(?:[^']|'')*'$/.test(raw)) fail('malformed single-quoted scalar');
      return raw.slice(1, -1).replaceAll("''", "'");
    }
    if (raw.startsWith('"')) {
      try { const value = JSON.parse(raw); if (typeof value !== 'string') fail('expected string'); return value; }
      catch { fail('malformed double-quoted scalar'); }
    }
    if (/^(true|false)$/.test(raw)) return raw === 'true';
    if (!raw || /[\n\r]|^(?:[&*!|>{\[]|---)|:\s|\s#/.test(raw)) fail('unsupported scalar syntax');
    return raw;
  }
  function list(raw) {
    if (!raw.startsWith('[') || !raw.endsWith(']')) fail('tools must be an inline list');
    const parts = []; let start = 1; let q = '';
    for (let i = 1; i < raw.length - 1; i++) {
      const c = raw[i];
      if (q === '"' && c === '\\') { i++; continue; }
      if (q && c === q) {
        if (q === "'" && raw[i + 1] === "'") { i++; continue; }
        q = '';
      } else if (!q && (c === "'" || c === '"')) q = c;
      else if (!q && c === ',') { parts.push(raw.slice(start, i)); start = i + 1; }
    }
    if (q) fail('unterminated tools string');
    if (raw.slice(start, -1).trim()) parts.push(raw.slice(start, -1));
    return parts.map(scalar);
  }
  const data = {}; let skipped = false;
  for (const line of match[1].split(/\r?\n/)) {
    if (!line.trim() || /^\s*#/.test(line)) continue;
    if (/^\s/.test(line)) { if (skipped) continue; fail('unsupported nested retained field'); }
    const field = /^([A-Za-z][\w-]*):(?:\s+(.*)|\s*)$/.exec(line);
    if (!field) fail('malformed field');
    const [, key, raw = ''] = field;
    skipped = discarded.has(key);
    if (skipped) continue;
    if (!retained.has(key)) fail(`unsupported field ${key}`);
    if (Object.hasOwn(data, key)) fail(`duplicate ${key}`);
    data[key] = key === 'tools' ? list(raw.trim()) : scalar(raw);
  }
  for (const key of ['name', 'description', 'applyTo']) {
    if (Object.hasOwn(data, key) && typeof data[key] !== 'string') fail(`${key} must be a string`);
  }
  if (Object.hasOwn(data, 'disable-model-invocation') && typeof data['disable-model-invocation'] !== 'boolean') fail('disable-model-invocation must be boolean');
  return { data, body: text.slice(match[0].length) };
}

const toolMap = {
  agent: ['invoke_subagent'], read: ['view_file', 'list_dir'],
  search: ['find_by_name', 'grep_search'], edit: ['write_to_file', 'replace_file_content', 'multi_replace_file_content'],
  execute: ['run_command'], 'execute/runInTerminal': ['run_command'], 'execute/getTerminalOutput': ['run_command'],
  web: ['read_url_content', 'search_web'], 'web/fetch': ['read_url_content'],
  'vscode/askQuestions': ['ask_question'], 'vscode/memory': ['view_file', 'write_to_file'],
  'vscode/toolSearch': [], todo: ['manage_task'], 'mudblazor/*': [], 'aspire-dashboard/*': []
};
const planningBoundary = `Planning/auditing write boundary: write_to_file, replace_file_content and multi_replace_file_content are forbidden on any resolved path outside docs/plans/**. No terminal writes, alternative tools, traversal or symlink escapes may bypass this restriction. This is a prompt-only boundary, not hook-backed enforcement.\n`;
export function convertAgent(text, file, diagnostics = () => {}) {
  const { data, body } = frontmatter(text, file);
  if (!data.name || !data.description || !Array.isArray(data.tools) || data.tools.some(t => typeof t !== 'string')) throw new Error(`${file}: name, description and tools required`);
  const tools = [...new Set(data.tools.flatMap(tool => {
    if (!Object.hasOwn(toolMap, tool)) throw new Error(`${file}: unsupported tool ${tool}`);
    if (!toolMap[tool].length) diagnostics(`${file}: ${tool} is not a native tool; discover optional integrations separately in the host.`);
    return toolMap[tool];
  }))];
  const planning = /cat-(?:planner|auditor)/.test(file);
  const preamble = `Antigravity adaptation: use research for read-only exploration and invoke_subagent for delegation, respecting all source role restrictions. Switch agents manually; handoff buttons and Copilot .prompt.md routing are not native here. Clowder hooks are not installed. Session notes use docs/plans/.clowder-notes/. Before notes in a git project, have the user or installer add the anchored project-relative notes directory to the actual git info/exclude file; planners/auditors may not edit that file themselves or bypass their write boundary. Optional MCP tools must be discovered from installed host integrations; never guess tool names.\n${planning ? planningBoundary : ''}\n`;
  let translated = body.replaceAll('/memories/session/', 'docs/plans/.clowder-notes/').replaceAll('/memories/', 'docs/plans/.clowder-notes/')
    .replace(/#tool:([\w/-]+)/g, (_, tool) => {
      if (!Object.hasOwn(toolMap, tool)) throw new Error(`${file}: unsupported executable tool reference ${tool}`);
      return tool === 'vscode/memory' ? 'the notes file tools' : (toolMap[tool][0] || 'host integration discovery');
    })
    .replace(/vscode_askQuestions|vscode\/askQuestions|askQuestions/g, 'ask_question')
    .replace(/\btoolSearch\b/g, 'host integration discovery')
    .replace(/\bExplore\b/g, 'research')
    .replace(/A `planner-write-guard` hook enforces[^.\n]*\./g, 'The write boundary is prompt-only on this harness.')
    .replace(/The `graphify-sync` hook builds,[^.\n]*\./g, 'Clowder graphify-sync hooks are not installed on this harness; use an existing graph if available.');
  return `---\nname: ${quote(data.name)}\ndescription: ${quote(data.description)}\ntools: ${quote(tools)}\nmainAgent: true\nsubagent: ${data['disable-model-invocation'] !== true}\n---\n${preamble}${translated}`;
}
export function convertRule(text, file) {
  const { data, body } = frontmatter(text, file);
  if (!data.description || !data.applyTo) throw new Error(`${file}: description and applyTo required`);
  return `---\ntrigger: glob\nglobs: ${quote(data.applyTo)}\ndescription: ${quote(data.description)}\n---\n${body}`;
}

// String-aware JSONC tokens retain offsets so edits never reserialize user configuration.
export function parseJsonc(text) {
  let i = text.charCodeAt(0) === 0xFEFF ? 1 : 0;
  function trivia() {
    while (i < text.length) {
      if (/\s/.test(text[i])) { i++; continue; }
      if (text.slice(i, i + 2) === '//') { i += 2; while (i < text.length && !/[\r\n]/.test(text[i])) i++; continue; }
      if (text.slice(i, i + 2) === '/*') {
        const end = text.indexOf('*/', i + 2);
        if (end < 0) throw new Error('unterminated JSONC comment');
        i = end + 2; continue;
      }
      break;
    }
  }
  function string() {
    const start = i++;
    while (i < text.length) {
      if (text[i] === '\\') { i += 2; continue; }
      if (text[i++] === '"') return { start, end: i, value: JSON.parse(text.slice(start, i)) };
    }
    throw new Error('unterminated JSONC string');
  }
  function value() {
    trivia(); const start = i; const c = text[i];
    if (c === '"') return string();
    if (c === '{' || c === '[') {
      i++; const members = []; const values = []; const result = c === '{' ? Object.create(null) : [];
      trivia();
      while (text[i] !== (c === '{' ? '}' : ']')) {
        if (i >= text.length) throw new Error('unterminated JSONC object/array');
        let key;
        if (c === '{') {
          if (text[i] !== '"') throw new Error('JSONC object key must be quoted');
          key = string(); trivia();
          if (text[i++] !== ':') throw new Error('missing JSONC colon');
        }
        const node = value();
        if (key) { members.push({ key: key.value, node }); result[key.value] = node.value; }
        else { values.push(node); result.push(node.value); }
        trivia();
        if (text[i] === ',') { i++; trivia(); }
        else if (text[i] !== (c === '{' ? '}' : ']')) throw new Error('missing JSONC comma');
      }
      const close = i++;
      return { start, end: i, close, value: result, members: c === '{' ? members : undefined, values };
    }
    while (i < text.length && !/[\s,\]}\/]/.test(text[i])) i++;
    if (i === start) throw new Error('invalid JSONC value');
    const result = JSON.parse(text.slice(start, i));
    return { start, end: i, value: result };
  }
  const root = value(); trivia();
  if (i !== text.length) throw new Error('unexpected JSONC content');
  return root;
}
function member(node, key, insensitive = false) {
  if (!object(node.value)) throw new Error(`${key}: parent must be an object`);
  const found = node.members.filter(m => insensitive ? m.key.toLowerCase() === key.toLowerCase() : m.key === key);
  if (found.length > 1 || (insensitive && found[0] && found[0].key !== key)) throw new Error(`ambiguous duplicate/case variant ${key}`);
  return found[0]?.node;
}
function insertProperty(text, node, key, value) {
  const newline = text.includes('\r\n') ? '\r\n' : '\n';
  const base = /^[ \t]*/.exec(text.slice(text.lastIndexOf('\n', node.start - 1) + 1))[0];
  const indent = base + '  ';
  const encoded = JSON.stringify(value, null, 2).replace(/\n/g, newline + indent);
  const last = node.members.at(-1)?.node;
  let prefix = text.slice(0, node.close);
  if (last) {
    const tail = text.slice(last.end, node.close);
    const trailing = parseJsonc(`{"x":0${tail}}`).members.length === 1 && /^\s*,/.test(tail.replace(/\/\*[\s\S]*?\*\/|\/\/[^\r\n]*/g, ''));
    if (!trailing) prefix = text.slice(0, last.end) + ',' + text.slice(last.end, node.close);
  }
  return prefix + newline + indent + quote(key) + ': ' + encoded + newline + base + text.slice(node.close);
}
export function mergeMcp(text, key, version, cache, { checkDnx = () => {} } = {}) {
  const root = parseJsonc(text);
  if (!object(root.value)) throw new Error('MCP root must be an object');
  const servers = member(root, key);
  if (servers && !object(servers.value)) throw new Error(`${key} must be an object`);
  const existing = servers && member(servers, 'mudblazor', true);
  if (existing && !object(existing.value)) throw new Error('mudblazor must be an object');
  if (existing) {
    const command = member(existing, 'command');
    const args = member(existing, 'args');
    if (command && typeof command.value !== 'string') throw new Error('mudblazor.command must be a string');
    if (args && (!Array.isArray(args.value) || args.value.some(a => typeof a !== 'string'))) throw new Error('mudblazor.args must be a string array');
  }
  const env = existing && member(existing, 'env');
  if (env && !object(env.value)) throw new Error('mudblazor.env must be an object');
  if (env) member(env, 'MUDBLAZOR_VERSION');
  if (version !== undefined && !/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(version)) throw new Error('Pass a valid -MudBlazorVersion / --mudblazor-version (for example 8.15.0)');
  if (existing) {
    if (version === undefined) return text;
    const args = member(existing, 'args');
    if (Array.isArray(args?.value) && args.value.some(a => typeof a === 'string' && /^--version(?:=|$)/.test(a))) throw new Error('Existing mudblazor args --version override conflicts with requested environment version; resolve it explicitly.');
    if (!env) return insertProperty(text, existing, 'env', { MUDBLAZOR_VERSION: version });
    const field = member(env, 'MUDBLAZOR_VERSION');
    if (!field) return insertProperty(text, env, 'MUDBLAZOR_VERSION', version);
    if (field.value === version) return text;
    return text.slice(0, field.start) + quote(version) + text.slice(field.end);
  }
  if (version === undefined) throw new Error('New mudblazor requires -MudBlazorVersion / --mudblazor-version.');
  checkDnx();
  const definition = { command: 'dnx', args: ['MudMCP', '--yes', '--', '--stdio'], env: { MUDBLAZOR_VERSION: version, MudBlazor__Repository__DataPath: path.resolve(cache) } };
  return servers ? insertProperty(text, servers, 'mudblazor', definition) : insertProperty(text, root, key, { mudblazor: definition });
}

export function safeDestination(file) {
  let current = path.resolve(file);
  while (true) {
    try { if (fs.lstatSync(current).isSymbolicLink()) throw new Error(`Refusing linked destination: ${current}`); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
}
export function atomicWrite(file, content, io = fs) {
  safeDestination(file);
  if (io.existsSync(file)) {
    const existing = io.readFileSync(file);
    if (existing.equals(Buffer.isBuffer(content) ? content : Buffer.from(content, 'utf8'))) return false;
  }
  io.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = `${file}.clowder-${process.pid}-${Date.now()}.tmp`;
  const mode = io.existsSync(file) ? io.statSync(file).mode : 0o600;
  const descriptor = io.openSync(temporary, 'wx', mode);
  let closed = false;
  try {
    io.writeFileSync(descriptor, content, { encoding: 'utf8' });
    io.closeSync(descriptor);
    closed = true;
    io.renameSync(temporary, file);
  } finally {
    if (!closed) io.closeSync(descriptor);
    if (io.existsSync(temporary)) io.unlinkSync(temporary);
  }
  return true;
}
export function profilePaths(home, platform = process.platform, env = process.env) {
  const base = platform === 'win32' ? env.APPDATA : platform === 'darwin' ? path.join(home, 'Library', 'Application Support') : env.XDG_CONFIG_HOME || path.join(home, '.config');
  if (!base) throw new Error('APPDATA is required; alternatively pass -CopilotMcpPath / --copilot-mcp-path.');
  return ['Code', 'Code - Insiders'].map(editor => path.join(base, editor, 'User'));
}
export function expandHome(value, home) {
  return value === '~' ? home : /^~[\\/]/.test(value) ? path.join(home, value.slice(2).replace(/[\\/]/g, path.sep)) : path.resolve(value);
}
function dnxCheck() {
  const dotnet = spawnSync('dotnet', ['--list-sdks'], { encoding: 'utf8' });
  const dnx = spawnSync(process.platform === 'win32' ? 'where.exe' : 'which', ['dnx'], { encoding: 'utf8' });
  if (dotnet.status !== 0 || !/^(?:[1-9]\d|[1-9]\d{2,})\.\d+\./m.test(dotnet.stdout || '') || dnx.status !== 0) throw new Error('New MudMCP registration requires .NET 10 SDK (or later) and dnx on PATH; install them separately.');
}
export function notesExclusion(project, run = spawnSync) {
  const git = args => run('git', ['-C', project, ...args], { encoding: 'utf8' });
  const root = git(['rev-parse', '--show-toplevel']);
  if (root.status !== 0) return undefined;
  const exclude = git(['rev-parse', '--git-path', 'info/exclude']);
  if (exclude.status !== 0) throw new Error('Cannot resolve git info/exclude');
  const file = path.resolve(project, exclude.stdout.trim());
  const relative = path.relative(root.stdout.trim(), path.join(project, 'docs', 'plans', '.clowder-notes')).split(path.sep).join('/');
  const pattern = '/' + relative.replace(/[\\*?[\] #!]/g, '\\$&') + '/';
  const original = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
  const newline = original.includes('\r\n') ? '\r\n' : '\n';
  return { file, content: original.split(/\r?\n/).includes(pattern) ? original : original + (original && !original.endsWith('\n') ? newline : '') + pattern + newline };
}
export function install(options, { home = os.homedir(), platform = process.platform, env = process.env, checkDnx = dnxCheck, log = console.log } = {}) {
  const { repo, harness = 'copilot', mud = false, globalMcp = false, version, mcpPath } = options;
  const project = options.project && expandHome(options.project, home);
  if (!['copilot', 'antigravity', 'all'].includes(harness)) throw new Error('Invalid harness');
  if (project && (!fs.existsSync(project) || !fs.statSync(project).isDirectory())) throw new Error('Project directory not found');
  if (mcpPath && (!globalMcp || harness === 'antigravity')) throw new Error('CopilotMcpPath requires GlobalMudMcp and a Copilot target');
  if (version !== undefined && !(mud || globalMcp) ) throw new Error('MudBlazorVersion requires MudBlazor or GlobalMudMcp');
  if (version !== undefined && !project && !globalMcp) throw new Error('MudBlazorVersion requires project MCP registration or GlobalMudMcp');
  const writes = []; const removals = [];
  const selectedMud = mud || globalMcp;
  const targets = harness === 'all' ? ['copilot', 'antigravity'] : [harness];
  for (const target of targets) {
    const base = project ? path.join(project, target === 'copilot' ? '.github' : '.agents') : path.join(home, target === 'copilot' ? '.copilot' : '.gemini/config');
    safeDestination(base);
    if (fs.existsSync(base) && !fs.statSync(base).isDirectory()) throw new Error(`Expected directory: ${base}`);
    if (target === 'copilot') {
      for (const directory of ['agents', 'instructions', 'skills']) {
        const destination = path.join(base, directory);
        safeDestination(destination);
        if (fs.existsSync(destination) && !fs.statSync(destination).isDirectory()) throw new Error(`Expected directory: ${destination}`);
        for (const entry of fs.readdirSync(path.join(repo, directory), { withFileTypes: true })) {
          const file = path.join(destination, entry.name);
          safeDestination(file);
          if (entry.isFile() && fs.existsSync(file) && !fs.statSync(file).isFile()) throw new Error(`Expected file: ${file}`);
        }
      }
    }
    for (const stem of optionalAgents) {
      if (!selectedMud) for (const suffix of ['.agent.md', '.md']) removals.push(path.join(base, 'agents', stem + suffix));
    }
    for (const name of fs.readdirSync(path.join(repo, 'skills'))) {
      if (!selectedMud && name.startsWith('cat-mudblazor-')) removals.push(path.join(base, 'skills', name));
    }
    if (target === 'antigravity') {
      for (const name of fs.readdirSync(path.join(repo, 'agents')).filter(n => n.endsWith('.agent.md'))) {
        if (!selectedMud && optionalAgents.includes(name.replace(/\.agent\.md$/, ''))) continue;
        writes.push({ file: path.join(base, 'agents', name.replace(/\.agent\.md$/, '.md')), content: convertAgent(fs.readFileSync(path.join(repo, 'agents', name), 'utf8'), name, log) });
      }
      for (const name of fs.readdirSync(path.join(repo, 'instructions')).filter(n => n.endsWith('.instructions.md'))) {
        writes.push({ file: path.join(base, 'rules', 'clowder-' + name.replace(/\.instructions\.md$/, '.md')), content: convertRule(fs.readFileSync(path.join(repo, 'instructions', name), 'utf8'), name) });
      }
      function skillTree(source, destination) {
        for (const item of fs.readdirSync(source, { withFileTypes: true })) {
          if (item.isSymbolicLink()) throw new Error(`Refusing linked source skill ${item.name}`);
          if (item.isDirectory()) skillTree(path.join(source, item.name), path.join(destination, item.name));
          else writes.push({ file: path.join(destination, item.name), content: fs.readFileSync(path.join(source, item.name)) });
        }
      }
      for (const name of fs.readdirSync(path.join(repo, 'skills'))) {
        if (!selectedMud && name.startsWith('cat-mudblazor-')) continue;
        skillTree(path.join(repo, 'skills', name), path.join(base, 'skills', name));
      }
      if (project) {
        const exclusion = notesExclusion(project);
        if (exclusion) writes.push(exclusion); else log('Non-git project: skipping notes exclusion; add it before creating notes in a future git project.');
      } else {
        const file = path.join(home, '.gemini', 'GEMINI.md');
        const old = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
        const start = '<!-- clowder:start -->'; const end = '<!-- clowder:end -->';
        const block = `${start}\nClowder scoped rules: ~/.gemini/config/rules/clowder-*.md. Select agents manually. Clowder hook enforcement is not ported. Before session notes, exclude docs/plans/.clowder-notes/ using the actual local git info/exclude path.\n${end}`;
        if ((old.split(start).length !== old.split(end).length) || old.split(start).length > 2 || (old.includes(start) && old.indexOf(start) > old.indexOf(end))) throw new Error('Malformed Clowder GEMINI section');
        const content = old.includes(start) ? old.replace(/<!-- clowder:start -->[\s\S]*?<!-- clowder:end -->/, block) : old + (old && !old.endsWith('\n') ? '\n' : '') + block + '\n';
        writes.push({ file, content });
      }
    }
    if (selectedMud && (project || globalMcp)) {
      let configs;
      if (target === 'antigravity') configs = [path.join(globalMcp ? path.join(home, '.gemini/config') : path.join(project, '.agents'), 'mcp_config.json')];
      else if (!globalMcp) configs = [path.join(project, '.vscode', 'mcp.json')];
      else if (mcpPath) configs = [expandHome(mcpPath, home)];
      else {
        configs = profilePaths(home, platform, env).filter(dir => fs.existsSync(dir) && fs.statSync(dir).isDirectory()).map(dir => path.join(dir, 'mcp.json'));
        if (!configs.length) throw new Error('No existing Stable/Insiders User directories; pass -CopilotMcpPath / --copilot-mcp-path for your profile.');
      }
      for (const file of configs) {
        const text = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '{}\n';
        let content;
        try { content = mergeMcp(text, target === 'copilot' ? 'servers' : 'mcpServers', version, path.join(home, '.mudmcp'), { checkDnx }); }
        catch (error) { throw new Error(`${file}: ${error.message}`); }
        writes.push({ file, content });
      }
    }
  }
  // Validate every planned destination and conversion before the first mutation.
  for (const { file } of writes) {
    safeDestination(file);
    if (fs.existsSync(file) && !fs.statSync(file).isFile()) throw new Error(`Expected file: ${file}`);
    if (fs.existsSync(file)) fs.accessSync(file, fs.constants.W_OK);
    let parent = path.dirname(file);
    while (!fs.existsSync(parent)) parent = path.dirname(parent);
    if (!fs.statSync(parent).isDirectory()) throw new Error(`Expected directory: ${parent}`);
    fs.accessSync(parent, fs.constants.W_OK);
  }
  for (const file of removals) {
    safeDestination(file);
    if (file.endsWith('.md') && fs.existsSync(file) && !fs.statSync(file).isFile()) throw new Error(`Expected optional agent file: ${file}`);
  }
  for (const { file, content } of writes) atomicWrite(file, content);
  for (const file of removals) if (fs.existsSync(file)) { fs.rmSync(file, { recursive: true }); log(`Removed owned optional content: ${file}`); }
  if (targets.includes('antigravity')) log('Antigravity: installed converted agents/rules/skills; Clowder hooks and companion skill placement are not ported.');
  if (project && globalMcp) log('Explicit GlobalMudMcp exception: global MCP configuration selected; no workspace MCP registration written.');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const options = {};
    for (let i = 2; i < process.argv.length; i += 2) {
      const key = process.argv[i]; const value = process.argv[i + 1];
      if (!['repo', 'project', 'harness', 'mud', 'globalMcp', 'version', 'mcpPath'].includes(key) || value === undefined) throw new Error(`Invalid helper argument: ${key}`);
      options[key] = ['mud', 'globalMcp'].includes(key) ? value === 'true' : value;
    }
    install(options);
  } catch (error) { console.error(`Clowder installation failed: ${error.message}`); process.exitCode = 1; }
}
