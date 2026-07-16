import XCTest
@testable import GRump

final class SyntaxHighlighterTests: XCTestCase {

    // MARK: - Basic tokenization

    func testEmptyLineReturnsPlainSpace() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].kind, .plain)
    }

    // MARK: - Swift keywords

    func testSwiftKeywordsDetected() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("func hello() {")
        let funcToken = tokens.first { $0.text == "func" }
        XCTAssertNotNil(funcToken)
        XCTAssertEqual(funcToken?.kind, .keyword)
    }

    func testSwiftLetKeyword() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("let x = 5")
        let letToken = tokens.first { $0.text == "let" }
        XCTAssertNotNil(letToken)
        XCTAssertEqual(letToken?.kind, .keyword)
    }

    func testSwiftReturnKeyword() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("return value")
        let returnToken = tokens.first { $0.text == "return" }
        XCTAssertNotNil(returnToken)
        XCTAssertEqual(returnToken?.kind, .keyword)
    }

    // MARK: - Types

    func testSwiftTypeDetected() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("let x: String")
        let stringToken = tokens.first { $0.text == "String" }
        XCTAssertNotNil(stringToken)
        XCTAssertEqual(stringToken?.kind, .type)
    }

    func testSwiftCapitalizedWordAsType() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("let view: MyCustomView")
        let customToken = tokens.first { $0.text == "MyCustomView" }
        XCTAssertNotNil(customToken)
        XCTAssertEqual(customToken?.kind, .type)
    }

    // MARK: - Strings

    func testDoubleQuotedString() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("let s = \"hello world\"")
        let stringToken = tokens.first { $0.kind == .string }
        XCTAssertNotNil(stringToken)
        XCTAssertTrue(stringToken!.text.contains("hello"))
    }

    func testSingleQuotedString() {
        let hl = SyntaxHighlighter(language: "python")
        let tokens = hl.highlight("x = 'hello'")
        let stringToken = tokens.first { $0.kind == .string }
        XCTAssertNotNil(stringToken)
    }

    func testEscapedStringCharacter() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("let s = \"hello\\nworld\"")
        let stringToken = tokens.first { $0.kind == .string }
        XCTAssertNotNil(stringToken)
        XCTAssertTrue(stringToken!.text.contains("\\n"))
    }

    // MARK: - Comments

    func testLineComment() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("// this is a comment")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].kind, .comment)
    }

    func testPythonHashComment() {
        let hl = SyntaxHighlighter(language: "python")
        let tokens = hl.highlight("# python comment")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].kind, .comment)
    }

    func testInlineComment() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("let x = 5 // inline")
        let commentTokens = tokens.filter { $0.kind == .comment }
        XCTAssertFalse(commentTokens.isEmpty)
    }

    func testBlockComment() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("/* block */ code")
        let commentTokens = tokens.filter { $0.kind == .comment }
        XCTAssertFalse(commentTokens.isEmpty)
    }

    // MARK: - Numbers

    func testIntegerNumber() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("let x = 42")
        let numToken = tokens.first { $0.text == "42" }
        XCTAssertNotNil(numToken)
        XCTAssertEqual(numToken?.kind, .number)
    }

    func testFloatingPointNumber() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("let pi = 3.14")
        let numToken = tokens.first { $0.text == "3.14" }
        XCTAssertNotNil(numToken)
        XCTAssertEqual(numToken?.kind, .number)
    }

    func testHexNumber() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("let c = 0xFF")
        let numToken = tokens.first { $0.kind == .number }
        XCTAssertNotNil(numToken)
        XCTAssertTrue(numToken!.text.hasPrefix("0x"))
    }

    // MARK: - JavaScript

    func testJavaScriptKeywords() {
        let hl = SyntaxHighlighter(language: "javascript")
        let tokens = hl.highlight("const x = async () => {}")
        let constToken = tokens.first { $0.text == "const" }
        let asyncToken = tokens.first { $0.text == "async" }
        XCTAssertEqual(constToken?.kind, .keyword)
        XCTAssertEqual(asyncToken?.kind, .keyword)
    }

    func testTypeScriptRecognized() {
        let hl = SyntaxHighlighter(language: "typescript")
        let tokens = hl.highlight("interface Foo {}")
        let ifToken = tokens.first { $0.text == "interface" }
        XCTAssertEqual(ifToken?.kind, .keyword)
    }

    func testTemplateLiteralInJS() {
        let hl = SyntaxHighlighter(language: "js")
        let tokens = hl.highlight("const s = `hello`")
        let stringToken = tokens.first { $0.kind == .string }
        XCTAssertNotNil(stringToken)
    }

    // MARK: - Python

    func testPythonKeywords() {
        let hl = SyntaxHighlighter(language: "python")
        let tokens = hl.highlight("def my_func():")
        let defToken = tokens.first { $0.text == "def" }
        XCTAssertEqual(defToken?.kind, .keyword)
    }

    func testPythonTypes() {
        let hl = SyntaxHighlighter(language: "python")
        let tokens = hl.highlight("x: int = 5")
        let intToken = tokens.first { $0.text == "int" }
        XCTAssertEqual(intToken?.kind, .type)
    }

    // MARK: - Go

    func testGoKeywords() {
        let hl = SyntaxHighlighter(language: "go")
        let tokens = hl.highlight("func main() {")
        let funcToken = tokens.first { $0.text == "func" }
        XCTAssertEqual(funcToken?.kind, .keyword)
    }

    // MARK: - Rust

    func testRustKeywords() {
        let hl = SyntaxHighlighter(language: "rust")
        let tokens = hl.highlight("fn main() {")
        let fnToken = tokens.first { $0.text == "fn" }
        XCTAssertEqual(fnToken?.kind, .keyword)
    }

    func testRustTypes() {
        let hl = SyntaxHighlighter(language: "rust")
        let tokens = hl.highlight("let v: Vec<i32>")
        let vecToken = tokens.first { $0.text == "Vec" }
        XCTAssertEqual(vecToken?.kind, .type)
    }

    // MARK: - Shell

    func testShellCommentPrefix() {
        let hl = SyntaxHighlighter(language: "bash")
        let tokens = hl.highlight("# comment here")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].kind, .comment)
    }

    func testShellKeywords() {
        let hl = SyntaxHighlighter(language: "sh")
        let tokens = hl.highlight("if [ -f file ]; then")
        let ifToken = tokens.first { $0.text == "if" }
        XCTAssertEqual(ifToken?.kind, .keyword)
    }

    // MARK: - Ruby

    func testRubyKeywords() {
        let hl = SyntaxHighlighter(language: "ruby")
        let tokens = hl.highlight("def hello")
        let defToken = tokens.first { $0.text == "def" }
        XCTAssertEqual(defToken?.kind, .keyword)
    }

    // MARK: - Unknown language

    func testUnknownLanguageProducesPlainTokens() {
        let hl = SyntaxHighlighter(language: "brainfuck")
        let tokens = hl.highlight("let x = 5")
        // "let" should be plain since unknown language has no keywords
        let letToken = tokens.first { $0.text == "let" }
        XCTAssertEqual(letToken?.kind, .plain)
    }

    // MARK: - Language aliases

    func testPyAlias() {
        let hl = SyntaxHighlighter(language: "py")
        let tokens = hl.highlight("def f(): pass")
        let defToken = tokens.first { $0.text == "def" }
        XCTAssertEqual(defToken?.kind, .keyword)
    }

    func testTSXAlias() {
        let hl = SyntaxHighlighter(language: "tsx")
        let tokens = hl.highlight("const x = 1")
        let constToken = tokens.first { $0.text == "const" }
        XCTAssertEqual(constToken?.kind, .keyword)
    }

    func testGolangAlias() {
        let hl = SyntaxHighlighter(language: "golang")
        let tokens = hl.highlight("func main() {}")
        let funcToken = tokens.first { $0.text == "func" }
        XCTAssertEqual(funcToken?.kind, .keyword)
    }

    // MARK: - Mixed content

    func testMixedKeywordsAndStrings() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("let name = \"world\"")
        let keywords = tokens.filter { $0.kind == .keyword }
        let strings = tokens.filter { $0.kind == .string }
        XCTAssertFalse(keywords.isEmpty)
        XCTAssertFalse(strings.isEmpty)
    }

    func testOperatorsAreClassifiedAsPlain() {
        let hl = SyntaxHighlighter(language: "swift")
        let tokens = hl.highlight("x + y")
        let plusToken = tokens.first { $0.text == "+" }
        XCTAssertNotNil(plusToken)
        XCTAssertEqual(plusToken?.kind, .plain)
    }

    // MARK: - JSON

    func testJSONLiteralsAreKeywords() {
        let hl = SyntaxHighlighter(language: "json")
        let tokens = hl.highlight("{\"active\": true, \"parent\": null}")
        let trueToken = tokens.first { $0.text == "true" }
        XCTAssertEqual(trueToken?.kind, .keyword)
        let nullToken = tokens.first { $0.text == "null" }
        XCTAssertEqual(nullToken?.kind, .keyword)
    }

    func testJSONStringsAndNumbersHighlight() {
        let hl = SyntaxHighlighter(language: "json")
        let tokens = hl.highlight("{\"count\": 42}")
        let stringToken = tokens.first { $0.text == "\"count\"" }
        XCTAssertEqual(stringToken?.kind, .string)
        let numberToken = tokens.first { $0.text == "42" }
        XCTAssertEqual(numberToken?.kind, .number)
    }

    func testJSONAliasesResolve() {
        for alias in ["json", "jsonc", "json5", "jsonl", "ndjson"] {
            let hl = SyntaxHighlighter(language: alias)
            let tokens = hl.highlight("false")
            XCTAssertEqual(tokens.first?.kind, .keyword, "alias \(alias) should highlight literals")
        }
    }
}
