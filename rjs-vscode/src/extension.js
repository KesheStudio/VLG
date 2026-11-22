const vscode = require('vscode');

const DIAGNOSTIC_SOURCE = 'RJS';

function activate(context) {
  const diagnostics = vscode.languages.createDiagnosticCollection('rjs');
  context.subscriptions.push(diagnostics);

  const selector = { language: 'rjs', scheme: 'file' };

  context.subscriptions.push(vscode.languages.registerCompletionItemProvider(selector, {
    provideCompletionItems(document, position) {
      if (!vscode.workspace.getConfiguration('rjs').get('completion.enable', true)) return [];
      const items = [];
      const keywords = [
        ['import', 'import { ${1:Name} } from "${2:./file.rjs}"', 'Import an exported value'],
        ['export', 'export ${1:Name} {\n  ${2:field} = ${3:value}\n}', 'Declare an exported object'],
        ['main', 'export main {\n  ${1:name} = ${2:value}\n}', 'Entry point object'],
        ['true', 'true', 'Boolean true'], ['false', 'false', 'Boolean false'], ['null', 'null', 'Null value']
      ];
      for (const [label, body, detail] of keywords) {
        const item = new vscode.CompletionItem(label, vscode.CompletionItemKind.Keyword);
        item.insertText = new vscode.SnippetString(body);
        item.detail = detail;
        items.push(item);
      }
      const text = document.getText();
      const declared = new Set();
      const re = /\bexport\s+([A-Za-z_$][\w$]*)\s*\{/g;
      let match;
      while ((match = re.exec(text))) declared.add(match[1]);
      const imported = /\bimport\s*\{([^}]+)\}\s*from\s*"([^"]+)"/g;
      while ((match = imported.exec(text))) {
        for (const name of match[1].split(',').map(s => s.trim()).filter(Boolean)) declared.add(name);
      }
      for (const name of declared) {
        const item = new vscode.CompletionItem(name, vscode.CompletionItemKind.Reference);
        item.detail = 'RJS symbol';
        items.push(item);
      }
      return items;
    }
  }, '.', '{', ' '));

  context.subscriptions.push(vscode.languages.registerHoverProvider(selector, {
    provideHover(document, position) {
      const word = document.getWordRangeAtPosition(position, /[A-Za-z_$][\w$]*/);
      if (!word) return;
      const value = document.getText(word);
      const docs = {
        import: '**import** — 从另一个 `.rjs` 文件导入已导出的名称。\n\n`import { Name } from "./file.rjs"`',
        export: '**export** — 声明一个可被其他 RJS 文件引用的对象。',
        main: '**main** — 入口对象。解析结果只输出 `main` 中实际引用到的内容。',
        null: '**null** — 空值。',
        true: '**true** — 布尔真值。',
        false: '**false** — 布尔假值。'
      };
      return docs[value] ? new vscode.Hover(new vscode.MarkdownString(docs[value])) : undefined;
    }
  }));

  context.subscriptions.push(vscode.languages.registerDocumentSymbolProvider(selector, {
    provideDocumentSymbols(document) {
      const symbols = [];
      const text = document.getText();
      const re = /^\s*export\s+([A-Za-z_$][\w$]*)\s*\{/gm;
      let match;
      while ((match = re.exec(text))) {
        const start = document.positionAt(match.index);
        const nameStart = document.positionAt(match.index + match[0].indexOf(match[1]));
        const open = text.indexOf('{', match.index);
        const close = findMatchingBrace(text, open);
        const end = document.positionAt(close >= 0 ? close + 1 : text.length);
        const range = new vscode.Range(start, end);
        const selection = new vscode.Range(nameStart, document.positionAt(match.index + match[0].indexOf(match[1]) + match[1].length));
        symbols.push(new vscode.DocumentSymbol(match[1], 'RJS export', vscode.SymbolKind.Object, range, selection));
      }
      return symbols;
    }
  }));

  context.subscriptions.push(vscode.languages.registerDefinitionProvider(selector, {
    async provideDefinition(document, position) {
      const range = document.getWordRangeAtPosition(position, /[A-Za-z_$][\w$]*/);
      if (!range) return;
      const name = document.getText(range);
      const text = document.getText();
      const local = new RegExp('\\bexport\\s+' + escapeRegExp(name) + '\\s*\\{').exec(text);
      if (local) return new vscode.Location(document.uri, document.positionAt(local.index + local[0].indexOf(name)));

      const importRe = /\bimport\s*\{([^}]+)\}\s*from\s*"([^"]+)"/g;
      let match;
      while ((match = importRe.exec(text))) {
        const importedNames = match[1].split(',').map(s => s.trim());
        if (!importedNames.includes(name)) continue;
        const target = vscode.Uri.joinPath(document.uri, '..', match[2]);
        try {
          const targetDoc = await vscode.workspace.openTextDocument(target);
          const targetMatch = new RegExp('\\bexport\\s+' + escapeRegExp(name) + '\\s*\\{').exec(targetDoc.getText());
          if (targetMatch) return new vscode.Location(targetDoc.uri, targetDoc.positionAt(targetMatch.index + targetMatch[0].indexOf(name)));
        } catch (_) { }
      }
      return;
    }
  }));

  const refresh = document => {
    if (document.languageId !== 'rjs') return;
    if (!vscode.workspace.getConfiguration('rjs').get('diagnostics.enable', true)) {
      diagnostics.delete(document.uri);
      return;
    }
    diagnostics.set(document.uri, validateDocument(document));
  };
  for (const document of vscode.workspace.textDocuments) refresh(document);
  context.subscriptions.push(vscode.workspace.onDidOpenTextDocument(refresh));
  context.subscriptions.push(vscode.workspace.onDidChangeTextDocument(e => refresh(e.document)));
  context.subscriptions.push(vscode.workspace.onDidSaveTextDocument(refresh));
  context.subscriptions.push(vscode.workspace.onDidCloseTextDocument(doc => diagnostics.delete(doc.uri)));

  context.subscriptions.push(vscode.commands.registerCommand('rjs.validateDocument', () => {
    const editor = vscode.window.activeTextEditor;
    if (editor && editor.document.languageId === 'rjs') {
      refresh(editor.document);
      vscode.window.showInformationMessage('RJS 检查完成');
    }
  }));
}

function findMatchingBrace(text, openIndex) {
  let depth = 0, quote = false, escaped = false, lineComment = false, blockComment = false;
  for (let i = openIndex; i < text.length; i++) {
    const c = text[i], n = text[i + 1];
    if (lineComment) { if (c === '\n') lineComment = false; continue; }
    if (blockComment) { if (c === '*' && n === '/') { blockComment = false; i++; } continue; }
    if (quote) { if (escaped) escaped = false; else if (c === '\\') escaped = true; else if (c === '"') quote = false; continue; }
    if (c === '/' && n === '/') { lineComment = true; i++; continue; }
    if (c === '/' && n === '*') { blockComment = true; i++; continue; }
    if (c === '"') { quote = true; continue; }
    if (c === '{') depth++;
    if (c === '}' && --depth === 0) return i;
  }
  return -1;
}

function validateDocument(document) {
  const text = document.getText();
  const issues = [];
  const stack = [];
  let quote = false, escaped = false, lineComment = false, blockComment = false, stringStart = -1, commentStart = -1;
  const pairs = { '}': '{', ']': '[', ')': '(' };
  for (let i = 0; i < text.length; i++) {
    const c = text[i], n = text[i + 1];
    if (lineComment) { if (c === '\n') lineComment = false; continue; }
    if (blockComment) { if (c === '*' && n === '/') { blockComment = false; i++; } continue; }
    if (quote) {
      if (escaped) escaped = false;
      else if (c === '\\') escaped = true;
      else if (c === '"') quote = false;
      continue;
    }
    if (c === '/' && n === '/') { lineComment = true; i++; continue; }
    if (c === '/' && n === '*') { blockComment = true; commentStart = i; i++; continue; }
    if (c === '"') { quote = true; stringStart = i; continue; }
    if ('{[('.includes(c)) stack.push({ char: c, index: i });
    else if (Object.prototype.hasOwnProperty.call(pairs, c)) {
      const top = stack.pop();
      if (!top || top.char !== pairs[c]) {
        issues.push(makeDiagnostic(document, i, i + 1, `不匹配的闭合符号 “${c}”`));
      }
    }
  }
  if (quote) issues.push(makeDiagnostic(document, stringStart, text.length, '字符串缺少结束双引号'));
  if (blockComment) issues.push(makeDiagnostic(document, commentStart, text.length, '块注释缺少结束符 */'));
  for (const item of stack) issues.push(makeDiagnostic(document, item.index, item.index + 1, `“${item.char}” 缺少对应的闭合符号`));

  const importRe = /^\s*import\b([^\n]*)/gm;
  let m;
  while ((m = importRe.exec(text))) {
    const line = m[0].trim();
    if (!/^import\s*\{\s*[\w$\s,]+\s*\}\s*from\s*"[^"\n]+"\s*$/.test(line)) {
      const start = document.positionAt(m.index);
      const end = document.positionAt(m.index + m[0].length);
      issues.push(new vscode.Diagnostic(new vscode.Range(start, end), 'import 格式应为：import { Name } from "./path.rjs"', vscode.DiagnosticSeverity.Error));
    }
  }
  const exportRe = /^\s*export\b([^\n]*)/gm;
  while ((m = exportRe.exec(text))) {
    const line = m[0].trim();
    if (!/^export\s+[A-Za-z_$][\w$]*\s*\{?\s*$/.test(line)) {
      const start = document.positionAt(m.index);
      const end = document.positionAt(m.index + m[0].length);
      issues.push(new vscode.Diagnostic(new vscode.Range(start, end), 'export 格式应为：export Name {', vscode.DiagnosticSeverity.Error));
    }
  }
  return issues;
}

function makeDiagnostic(document, start, end, message) {
  return new vscode.Diagnostic(new vscode.Range(document.positionAt(start), document.positionAt(end)), message, vscode.DiagnosticSeverity.Error);
}
function escapeRegExp(value) { return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
function deactivate() {}
module.exports = { activate, deactivate };
