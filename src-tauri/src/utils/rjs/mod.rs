use std::collections::{HashMap, HashSet};
use std::path::{Component, Path, PathBuf};

use serde_json::{Map, Number, Value};
use tauri::{AppHandle, Runtime};

#[allow(non_snake_case)]
use crate::utils::crypto::FileAPI;

// pub type RjsValue = Value;

#[derive(Debug, Clone)]
pub struct RjsDocument {
    // exports: Map<String, Value>,
    main: Value,
}

impl RjsDocument {
    // pub fn main(&self) -> &Value { &self.main }

    // pub fn into_main(self) -> Value { self.main }

    pub fn main_json(&self) -> Result<String, String> {
        serde_json::to_string(&self.main).map_err(|e| format!("failed to serialize RJS main as JSON: {e}"))
    }

    // pub fn main_json_pretty(&self) -> Result<String, String> {
    //     serde_json::to_string_pretty(&self.main).map_err(|e| format!("failed to serialize RJS main as JSON: {e}"))
    // }

    // pub fn export(&self, name: &str) -> Option<&Value> { self.exports.get(name) }
}

pub fn parse_resource<R: Runtime>(app: &AppHandle<R>, resource_path: &str) -> Result<RjsDocument, String> {
    let normalized = normalize_resource_path("", resource_path)?;
    ensure_rjs_extension(&normalized)?;
    let mut loader = Loader { app, active: HashSet::new() };
    let exports = loader.load(&normalized)?;
    make_document(exports, &normalized)
}

pub fn parse_resource_json<R: Runtime>(app: &AppHandle<R>, resource_path: &str) -> Result<String, String> {
    parse_resource(app, resource_path)?.main_json()
}

// pub fn parse_resource_value<R: Runtime>(app: &AppHandle<R>, resource_path: &str) -> Result<Value, String> {
//     Ok(parse_resource(app, resource_path)?.into_main())
// }

// pub fn parse_resource_json_pretty<R: Runtime>(app: &AppHandle<R>, resource_path: &str) -> Result<String, String> {
//     parse_resource(app, resource_path)?.main_json_pretty()
// }

// pub fn parse_str(source: &str) -> Result<RjsDocument, String> {
//     let mut parser = Parser::new(source)?;
//     let mut no_imports = |_path: &str| -> Result<HashMap<String, Value>, String> {
//         Err("imports require parse_resource() so they are loaded through FileAPI".into())
//     };
//     let exports = parser.parse(&mut no_imports)?;
//     make_document(exports, "<memory>")
// }

// pub fn parse_str_json(source: &str) -> Result<String, String> { parse_str(source)?.main_json() }

// pub fn parse_str_value(source: &str) -> Result<Value, String> { Ok(parse_str(source)?.into_main()) }

fn make_document(exports: HashMap<String, Value>, source: &str) -> Result<RjsDocument, String> {
    let main = exports.get("main").cloned().ok_or_else(|| format!("RJS entry '{source}' must export `main`"))?;
    if !main.is_object() {
        return Err(format!("RJS entry '{source}' export `main` must be an object"));
    }
    // let exports = exports.into_iter().collect::<Map<String, Value>>();
    // Ok(RjsDocument { exports, main })
    Ok(RjsDocument { main })
}

struct Loader<'a, R: Runtime> {
    app: &'a AppHandle<R>,
    active: HashSet<String>,
}

impl<'a, R: Runtime> Loader<'a, R> {
    fn load(&mut self, path: &str) -> Result<HashMap<String, Value>, String> {
        if !self.active.insert(path.to_string()) {
            return Err(format!("cyclic RJS import detected at '{path}'"));
        }
        let result = (|| {
            let bytes = FileAPI::read_resource(self.app, path, true)?;
            let source = std::str::from_utf8(&bytes)
                .map_err(|e| format!("RJS file '{path}' is not valid UTF-8: {e}"))?;
            let mut parser = Parser::new(source).map_err(|e| format!("{path}: {e}"))?;
            let current = path.to_string();
            let mut import_loader = |specifier: &str| {
                let imported_path = resolve_import(&current, specifier)?;
                self.load(&imported_path)
            };
            parser.parse(&mut import_loader).map_err(|e| format!("{path}: {e}"))
        })();
        self.active.remove(path);
        result
    }
}

fn ensure_rjs_extension(path: &str) -> Result<(), String> {
    if Path::new(path).extension().and_then(|x| x.to_str()) == Some("rjs") { Ok(()) }
    else { Err(format!("RJS resource must use lowercase .rjs extension: {path}")) }
}

fn resolve_import(current_file: &str, specifier: &str) -> Result<String, String> {
    let spec = Path::new(specifier);
    if spec.is_absolute() { return Err(format!("absolute RJS imports are forbidden: '{specifier}'")); }
    let parent = Path::new(current_file).parent().unwrap_or_else(|| Path::new(""));
    let normalized = normalize_resource_path("", &parent.join(spec).to_string_lossy())?;
    ensure_rjs_extension(&normalized)?;
    Ok(normalized)
}

fn normalize_resource_path(base: &str, path: &str) -> Result<String, String> {
    let input = if base.is_empty() { PathBuf::from(path) } else { Path::new(base).join(path) };
    let mut parts: Vec<String> = Vec::new();
    for component in input.components() {
        match component {
            Component::CurDir => {},
            Component::Normal(part) => parts.push(part.to_string_lossy().to_string()),
            Component::ParentDir => if parts.pop().is_none() {
                return Err(format!("resource path escapes resource root: '{path}'"));
            },
            Component::RootDir | Component::Prefix(_) => return Err(format!("absolute resource path is forbidden: '{path}'")),
        }
    }
    if parts.is_empty() { return Err("empty RJS resource path".into()); }
    Ok(parts.join("/"))
}

#[derive(Debug, Clone, PartialEq)]
enum TokenKind {
    Ident(String), String(String), Number(String),
    LBrace, RBrace, LBracket, RBracket, LParen, RParen, Equal, Comma, Dot, End,
}
#[derive(Debug, Clone)]
struct Token { kind: TokenKind, offset: usize }

struct Lexer<'a> { source: &'a str, bytes: &'a [u8], pos: usize }
impl<'a> Lexer<'a> {
    fn new(source: &'a str) -> Self { Self { source, bytes: source.as_bytes(), pos: 0 } }

    fn tokenize(mut self) -> Result<Vec<Token>, String> {
        let mut tokens = Vec::new();
        loop {
            self.skip_space_and_comments()?;
            let offset = self.pos;
            if self.pos >= self.bytes.len() { tokens.push(Token { kind: TokenKind::End, offset }); break; }
            let kind = match self.bytes[self.pos] {
                b'{' => { self.pos += 1; TokenKind::LBrace },
                b'}' => { self.pos += 1; TokenKind::RBrace },
                b'[' => { self.pos += 1; TokenKind::LBracket },
                b']' => { self.pos += 1; TokenKind::RBracket },
                b'(' => { self.pos += 1; TokenKind::LParen },
                b')' => { self.pos += 1; TokenKind::RParen },
                b'=' => { self.pos += 1; TokenKind::Equal },
                b',' => { self.pos += 1; TokenKind::Comma },
                b'.' => { self.pos += 1; TokenKind::Dot },
                b'"' => TokenKind::String(self.read_string()?),
                b'-' | b'0'..=b'9' => TokenKind::Number(self.read_number()?),
                b if is_ident_start(b) => TokenKind::Ident(self.read_ident()),
                b => return Err(self.error_at(offset, format!("unexpected character '{}'", b as char))),
            };
            tokens.push(Token { kind, offset });
        }
        Ok(tokens)
    }

    fn skip_space_and_comments(&mut self) -> Result<(), String> {
        loop {
            while self.pos < self.bytes.len() && self.bytes[self.pos].is_ascii_whitespace() { self.pos += 1; }
            if self.pos + 1 >= self.bytes.len() || self.bytes[self.pos] != b'/' { return Ok(()); }
            match self.bytes[self.pos + 1] {
                b'/' => {
                    self.pos += 2;
                    while self.pos < self.bytes.len() && self.bytes[self.pos] != b'\n' { self.pos += 1; }
                },
                b'*' => {
                    let start = self.pos; self.pos += 2; let mut closed = false;
                    while self.pos + 1 < self.bytes.len() {
                        if self.bytes[self.pos] == b'*' && self.bytes[self.pos + 1] == b'/' { self.pos += 2; closed = true; break; }
                        self.pos += 1;
                    }
                    if !closed { return Err(self.error_at(start, "unterminated block comment")); }
                },
                _ => return Ok(()),
            }
        }
    }

    fn read_string(&mut self) -> Result<String, String> {
        let start = self.pos; self.pos += 1; let mut out = String::new();
        while self.pos < self.bytes.len() {
            let b = self.bytes[self.pos]; self.pos += 1;
            match b {
                b'"' => return Ok(out),
                b'\\' => {
                    if self.pos >= self.bytes.len() { return Err(self.error_at(start, "unterminated string escape")); }
                    let escaped = self.bytes[self.pos]; self.pos += 1;
                    match escaped {
                        b'"' => out.push('"'), b'\\' => out.push('\\'), b'n' => out.push('\n'),
                        b'r' => out.push('\r'), b't' => out.push('\t'), b'0' => out.push('\0'),
                        _ => return Err(self.error_at(self.pos - 1, "unsupported string escape")),
                    }
                },
                0..=0x7f => out.push(b as char),
                _ => {
                    let tail = &self.source[self.pos - 1..];
                    let ch = tail.chars().next().ok_or_else(|| self.error_at(start, "invalid UTF-8"))?;
                    out.push(ch); self.pos = self.pos - 1 + ch.len_utf8();
                }
            }
        }
        Err(self.error_at(start, "unterminated string"))
    }

    fn read_number(&mut self) -> Result<String, String> {
        let start = self.pos;
        while self.pos < self.bytes.len() {
            let b = self.bytes[self.pos];
            if b.is_ascii_digit() || matches!(b, b'.' | b'e' | b'E' | b'+' | b'-') { self.pos += 1; } else { break; }
        }
        let value = self.source[start..self.pos].to_string();
        let _: Number = serde_json::from_str(&value).map_err(|_| self.error_at(start, format!("invalid number '{value}'")))?;
        Ok(value)
    }

    fn read_ident(&mut self) -> String {
        let start = self.pos; self.pos += 1;
        while self.pos < self.bytes.len() && is_ident_continue(self.bytes[self.pos]) { self.pos += 1; }
        self.source[start..self.pos].to_string()
    }
    fn error_at(&self, offset: usize, message: impl Into<String>) -> String {
        format!("RJS parse error at byte {offset}: {}", message.into())
    }
}
fn is_ident_start(b: u8) -> bool { b.is_ascii_alphabetic() || b == b'_' || b == b'$' }
fn is_ident_continue(b: u8) -> bool { is_ident_start(b) || b.is_ascii_digit() || b == b'-' }

struct Parser {
    tokens: Vec<Token>, cursor: usize,
    globals: HashMap<String, Value>,
    scopes: Vec<HashMap<String, Value>>,
    seen_export: bool,
}
impl Parser {
    fn new(source: &str) -> Result<Self, String> {
        Ok(Self { tokens: Lexer::new(source).tokenize()?, cursor: 0, globals: HashMap::new(), scopes: Vec::new(), seen_export: false })
    }

    fn parse<F>(&mut self, import_loader: &mut F) -> Result<HashMap<String, Value>, String>
    where F: FnMut(&str) -> Result<HashMap<String, Value>, String> {
        let mut exports = HashMap::new();
        while !matches!(self.current().kind, TokenKind::End) {
            let keyword = self.expect_ident()?;
            match keyword.as_str() {
                "import" => {
                    if self.seen_export { return Err(self.error("imports must appear before the first export")); }
                    self.expect(TokenKind::LBrace)?;
                    let mut names = Vec::new();
                    loop {
                        names.push(self.expect_ident()?);
                        if self.consume(&TokenKind::Comma) { continue; }
                        break;
                    }
                    self.expect(TokenKind::RBrace)?;
                    self.expect_ident_value("from")?;
                    let specifier = match self.advance().kind.clone() {
                        TokenKind::String(s) => s,
                        _ => return Err(self.error("expected quoted import path")),
                    };
                    let imported = import_loader(&specifier)?;
                    for name in names {
                        let value = imported.get(&name).ok_or_else(|| self.error(format!("module '{specifier}' does not export '{name}'")))?.clone();
                        if self.globals.insert(name.clone(), value).is_some() { return Err(self.error(format!("duplicate imported symbol '{name}'"))); }
                    }
                },
                "export" => {
                    self.seen_export = true;
                    let name = self.expect_ident()?;
                    if self.globals.contains_key(&name) || exports.contains_key(&name) { return Err(self.error(format!("duplicate symbol '{name}'"))); }
                    let value = self.parse_value()?;
                    if !value.is_object() { return Err(self.error("an export must be an object: export name { ... }")); }
                    self.globals.insert(name.clone(), value.clone());
                    exports.insert(name, value);
                },
                other => return Err(self.error(format!("expected 'import' or 'export', found '{other}'"))),
            }
        }
        Ok(exports)
    }

    fn parse_value(&mut self) -> Result<Value, String> {
        match self.advance().kind.clone() {
            TokenKind::String(s) => Ok(Value::String(s)),
            TokenKind::Number(n) => serde_json::from_str(&n).map_err(|e| self.error(format!("invalid number: {e}"))),
            TokenKind::Ident(name) if name == "true" => Ok(Value::Bool(true)),
            TokenKind::Ident(name) if name == "false" => Ok(Value::Bool(false)),
            TokenKind::Ident(name) if name == "null" => Ok(Value::Null),
            TokenKind::Ident(name) => self.parse_reference_path(name),
            TokenKind::LBrace => self.parse_object_body(),
            TokenKind::LBracket => self.parse_array_body(),
            _ => Err(self.error("expected a value (string, number, boolean, null, reference, object, or array)")),
        }
    }

    fn parse_reference_path(&mut self, root: String) -> Result<Value, String> {
        let mut value = self.lookup(&root).cloned()
            .ok_or_else(|| self.error(format!("unknown or forward reference '{root}'")))?;
        let mut path = root;
        loop {
            if self.consume(&TokenKind::Dot) {
                let member = self.expect_ident()?;
                path.push('.');
                path.push_str(&member);
                value = value.get(&member).cloned().ok_or_else(|| {
                    self.error(format!("reference '{path}' does not exist or is not an object"))
                })?;
                continue;
            }

            if self.consume(&TokenKind::LBracket) {
                let parenthesized = self.consume(&TokenKind::LParen);
                let index_token = self.advance().clone();
                let index = match index_token.kind {
                    TokenKind::Number(raw) => {
                        if raw.chars().any(|c| matches!(c, '.' | 'e' | 'E' | '+' | '-')) {
                            return Err(self.error("array index must be a non-negative integer"));
                        }
                        raw.parse::<usize>()
                            .map_err(|_| self.error("array index is out of range"))?
                    }
                    _ => return Err(self.error("array index must be a non-negative integer")),
                };
                if parenthesized { self.expect(TokenKind::RParen)?; }
                self.expect(TokenKind::RBracket)?;
                path.push_str(&format!("[{index}]"));
                value = value.as_array()
                    .and_then(|items| items.get(index))
                    .cloned()
                    .ok_or_else(|| self.error(format!(
                        "reference '{path}' does not exist, is not an array, or index is out of range"
                    )))?;
                continue;
            }

            break;
        }
        Ok(value)
    }

    fn parse_object_body(&mut self) -> Result<Value, String> {
        self.scopes.push(HashMap::new());
        let result = (|| {
            let mut object = Map::new();
            while !self.consume(&TokenKind::RBrace) {
                if matches!(self.current().kind, TokenKind::End) { return Err(self.error("unterminated object; expected '}'")); }
                let key = self.expect_ident()?;
                self.expect(TokenKind::Equal)?;
                let value = self.parse_value()?;
                if self.scopes.last().expect("object scope exists").contains_key(&key) {
                    return Err(self.error(format!("duplicate field '{key}'")));
                }
                self.scopes.last_mut().expect("object scope exists").insert(key.clone(), value.clone());
                object.insert(key, value);
                if self.consume(&TokenKind::Comma) { continue; }
                if !matches!(self.current().kind, TokenKind::RBrace) { return Err(self.error("expected ',' or '}' after object field")); }
            }
            Ok(Value::Object(object))
        })();
        self.scopes.pop(); result
    }

    fn parse_array_body(&mut self) -> Result<Value, String> {
        let mut values = Vec::new();
        while !self.consume(&TokenKind::RBracket) {
            if matches!(self.current().kind, TokenKind::End) { return Err(self.error("unterminated array; expected ']'")); }
            values.push(self.parse_value()?);
            if self.consume(&TokenKind::Comma) { continue; }
            if !matches!(self.current().kind, TokenKind::RBracket) { return Err(self.error("expected ',' or ']' after array item")); }
        }
        Ok(Value::Array(values))
    }

    fn lookup(&self, name: &str) -> Option<&Value> {
        for scope in self.scopes.iter().rev() { if let Some(value) = scope.get(name) { return Some(value); } }
        self.globals.get(name)
    }
    fn current(&self) -> &Token { &self.tokens[self.cursor] }
    fn advance(&mut self) -> &Token {
        let index = self.cursor; if !matches!(self.tokens[index].kind, TokenKind::End) { self.cursor += 1; } &self.tokens[index]
    }
    fn consume(&mut self, kind: &TokenKind) -> bool { if &self.current().kind == kind { self.advance(); true } else { false } }
    fn expect(&mut self, kind: TokenKind) -> Result<(), String> { if self.consume(&kind) { Ok(()) } else { Err(self.error(format!("expected {kind:?}"))) } }
    fn expect_ident(&mut self) -> Result<String, String> { match self.advance().kind.clone() { TokenKind::Ident(v) => Ok(v), _ => Err(self.error("expected identifier")) } }
    fn expect_ident_value(&mut self, expected: &str) -> Result<(), String> {
        let got = self.expect_ident()?; if got == expected { Ok(()) } else { Err(self.error(format!("expected '{expected}', found '{got}'"))) }
    }
    fn error(&self, message: impl Into<String>) -> String { format!("RJS parse error at byte {}: {}", self.current().offset, message.into()) }
}

// #[cfg(test)]
// mod tests {
//     use super::*;

//     #[test]
//     fn main_is_the_only_assembled_output_and_arrays_work() {
//         let doc = parse_str(r#"
//             export constants { title = "RJS", port = 8080 }
//             export main {
//                 title = constants,
//                 list = [1, true, "154rjs", { a = 1, b = "x", c = a }],
//                 nested = { a = 7, b = a, list = [a, 8] }
//             }
//             export unused { hidden = "not emitted" }
//         "#).unwrap();
//         assert_eq!(doc.main()["list"][3]["c"], 1);
//         assert_eq!(doc.main()["nested"]["b"], 7);
//         assert!(doc.main_json().unwrap().contains("154rjs"));
//         assert!(!doc.main_json().unwrap().contains("not emitted"));
//         assert!(doc.export("unused").is_some());
//     }

//     #[test]
//     fn dotted_references_resolve_imported_or_local_object_members() {
//         let doc = parse_str(r#"
//             export Murasame { name = "Murasame", lastName = "Shigure", stats = { hp = 100 } }
//             export main {
//                 name = Murasame.name,
//                 lastName = Murasame.lastName,
//                 hp = Murasame.stats.hp,
//                 local = { title = "hello", copied = title }
//             }
//         "#).unwrap();
//         assert_eq!(doc.main()["name"], "Murasame");
//         assert_eq!(doc.main()["lastName"], "Shigure");
//         assert_eq!(doc.main()["hp"], 100);
//         assert_eq!(doc.main()["local"]["copied"], "hello");
//     }

//     #[test]
//     fn parses_string_arrays_and_supports_numeric_index_references() {
//         let doc = parse_str(r#"
//             export Murasame {
//                 name = "丛雨",
//                 lastName = "有地",
//                 imageList = ["image/Murasame/01.png"]
//             }
//             export main {
//                 image = Murasame.imageList[0],
//                 parenthesizedImage = Murasame.imageList[(0)],
//                 allImages = Murasame.imageList,
//                 nested = { rows = [{ name = "first" }, { name = "second" }] },
//                 secondName = nested.rows[1].name
//             }
//         "#).unwrap();
//         assert_eq!(doc.main()["image"], "image/Murasame/01.png");
//         assert_eq!(doc.main()["parenthesizedImage"], "image/Murasame/01.png");
//         assert_eq!(doc.main()["allImages"][0], "image/Murasame/01.png");
//         assert_eq!(doc.main()["secondName"], "second");
//     }

//     #[test]
//     fn array_index_rejects_non_integer_and_out_of_range() {
//         let decimal = parse_str(r#"export data { items = ["a"] } export main { x = data.items[0.5] }"#).unwrap_err();
//         assert!(decimal.contains("array index must be a non-negative integer"));
//         let missing = parse_str(r#"export data { items = ["a"] } export main { x = data.items[2] }"#).unwrap_err();
//         assert!(missing.contains("index is out of range"));
//     }

//     #[test]
//     fn dotted_reference_rejects_missing_member() {
//         let error = parse_str(r#"export source { a = 1 } export main { x = source.missing }"#).unwrap_err();
//         assert!(error.contains("reference 'source.missing' does not exist"));
//     }

//     #[test]
//     fn nearest_scope_wins_and_parent_scope_is_visible() {
//         let doc = parse_str(r#"export main { outer = 10, child = { inner = 20, copy = inner, inherited = outer }, copy = outer }"#).unwrap();
//         assert_eq!(doc.main()["child"]["copy"], 20);
//         assert_eq!(doc.main()["child"]["inherited"], 10);
//         assert_eq!(doc.main()["copy"], 10);
//     }

//     #[test]
//     fn rejects_forward_reference_and_field_cycles() {
//         let e = parse_str("export main { a = b, b = a }").unwrap_err();
//         assert!(e.contains("unknown or forward reference"));
//     }

//     #[test]
//     fn drops_comments_and_accepts_trailing_commas() {
//         let doc = parse_str("/* head */ export main { a = [1, 2,], // tail\n b = { ok = true, }, }").unwrap();
//         assert_eq!(doc.main()["a"][1], 2);
//         assert_eq!(doc.main()["b"]["ok"], true);
//     }

//     #[test]
//     fn requires_main_and_main_must_be_object() {
//         assert!(parse_str("export helper { x = 1 }").unwrap_err().contains("must export `main`"));
//         assert!(parse_str("export main { x = 1 } export bad { y = 2 }").is_ok());
//     }

//     #[test]
//     fn rejects_duplicate_fields() {
//         assert!(parse_str("export main { a = 1, a = 2 }").unwrap_err().contains("duplicate field"));
//     }
// }
