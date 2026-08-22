#include "Compiler.h"

#include <cctype>
#include <sstream>
#include <stdexcept>

// ============================================================
// Мини-C -> ASM. См. Compiler.h и ASSEMBLY.md, раздел "Мини-C".
//
// Общая идея кодогена выражений: правый операнд сначала в A,
// PUSH A, затем левый операнд в A, POP B - после этого A=левый,
// B=правый, готово для несимметричных операций (SUB и т.д.).
// Работает для сколь угодно вложенных выражений бесплатно, т.к.
// использует настоящий аппаратный стек CPU.
//
// У CPU нет инструкции "регистр в регистр" - единственный способ
// скопировать значение из одного регистра в другой не трогая
// исходный - PUSH исходный / POP целевой (PUSH только читает
// регистр, не изменяет его - см. ASSEMBLY.md, PUSH).
// ============================================================

// ---------------- Лексер ----------------

// Прелюдия устройств - готовые const/мапированные массивы для регистров
// Keyboard/Clock/VideoCard/PngLoader/MapLoader (см. ASSEMBLY.md), чтобы
// пользовательским .mc-программам не нужно было объявлять их руками -
// подмешивается перед пользовательским кодом в Compiler::lex() ниже.
// Адреса выверены по ASSEMBLY.md (разделы Keyboard/VideoCard/PngLoader/
// MapLoader) и по C/DEMOS/TILEDEMO.ASM. Компилятор не проверяет повторное
// объявление const/массива (см. collectDeclarations) - если пользователь
// объявит то же имя сам, его объявление просто перезапишет прелюдию, без
// ошибки.
static const std::string kDevicePrelude =
    "const KEYBOARD_DATA = 0xF0000005;\n"
    "const KEYBOARD_CONTROL = 0xF0000006;\n"
    "const CLOCK_LOW = 0xF0000FFC;\n"
    "const CLOCK_HIGH = 0xF0000FFD;\n"
    "const VIDEOCARD_X_LOW = 0xF0000FDE;\n"
    "const VIDEOCARD_X_HIGH = 0xF0000FDF;\n"
    "const VIDEOCARD_Y_LOW = 0xF0000FE0;\n"
    "const VIDEOCARD_Y_HIGH = 0xF0000FE1;\n"
    "const VIDEOCARD_W_LOW = 0xF0000FE2;\n"
    "const VIDEOCARD_W_HIGH = 0xF0000FE3;\n"
    "const VIDEOCARD_H_LOW = 0xF0000FE4;\n"
    "const VIDEOCARD_H_HIGH = 0xF0000FE5;\n"
    "const VIDEOCARD_R = 0xF0000FE6;\n"
    "const VIDEOCARD_G = 0xF0000FE7;\n"
    "const VIDEOCARD_B = 0xF0000FE8;\n"
    "const VIDEOCARD_COMMAND = 0xF0000FE9;\n"
    "const VIDEOCARD_STATUS = 0xF0000FEA;\n"
    "const VIDEOCARD_SPRITE_INDEX = 0xF0000FEB;\n"
    "const VIDEOCARD_SPRITE_PIXEL_LOW = 0xF0000FEC;\n"
    "const VIDEOCARD_SPRITE_PIXEL_HIGH = 0xF0000FED;\n"
    "const VIDEOCARD_SPRITE_X_LOW = 0xF0000FEE;\n"
    "const VIDEOCARD_SPRITE_X_HIGH = 0xF0000FEF;\n"
    "const VIDEOCARD_SPRITE_Y_LOW = 0xF0000FF0;\n"
    "const VIDEOCARD_SPRITE_Y_HIGH = 0xF0000FF1;\n"
    "const VIDEOCARD_SPRITE_VISIBLE = 0xF0000FF2;\n"
    "const VIDEOCARD_SPRITE_R = 0xF0000FF3;\n"
    "const VIDEOCARD_SPRITE_G = 0xF0000FF4;\n"
    "const VIDEOCARD_SPRITE_B = 0xF0000FF5;\n"
    "const VIDEOCARD_SPRITE_COMMAND = 0xF0000FF6;\n"
    "const VIDEOCARD_SPRITE_STATUS = 0xF0000FF7;\n"
    "const VIDEOCARD_SCROLL_X_LOW = 0xF0000FF8;\n"
    "const VIDEOCARD_SCROLL_X_HIGH = 0xF0000FF9;\n"
    "const VIDEOCARD_SCROLL_Y_LOW = 0xF0000FFA;\n"
    "const VIDEOCARD_SCROLL_Y_HIGH = 0xF0000FFB;\n"
    "const PNGLOADER_NAME0 = 0xF0000FFE;\n"
    "const PNGLOADER_SRC_X_LOW = 0xF000100A;\n"
    "const PNGLOADER_SRC_X_HIGH = 0xF000100B;\n"
    "const PNGLOADER_SRC_Y_LOW = 0xF000100C;\n"
    "const PNGLOADER_SRC_Y_HIGH = 0xF000100D;\n"
    "const PNGLOADER_SPRITE_INDEX = 0xF000100E;\n"
    "const PNGLOADER_COMMAND = 0xF000100F;\n"
    "const PNGLOADER_STATUS = 0xF0001010;\n"
    "const PNGLOADER_TILE_INDEX = 0xF0001011;\n"
    "int pngLoaderName[12] = 0xF0000FFE;\n"
    "const MAPLOADER_NAME0 = 0xF0001012;\n"
    "const MAPLOADER_COMMAND = 0xF000101E;\n"
    "const MAPLOADER_STATUS = 0xF000101F;\n"
    "int mapLoaderName[12] = 0xF0001012;\n";

static const char* kKeywords[] = {
    "int", "if", "else", "while", "for", "return", "const",
    "poke", "peek",
    "print_char", "print_str", "set_color", "clear_screen",
    "exec_child",
    "mod_load", "sound_play", "sound_stop", "sound_pause",
    "sound_resume", "sound_set_volume",
    "str_copy"
};

void Compiler::lex(const std::string& source)
{
    tokens.clear();
    lexChunk(kDevicePrelude, 1);
    lexChunk(source, 1);
    tokens.push_back({ TokType::END, "", 0, 1 });
}

void Compiler::lexChunk(const std::string& source, int startLine)
{
    int line = startLine;
    size_t i = 0;
    size_t n = source.size();

    const auto& keywords = kKeywords;

    while (i < n)
    {
        char c = source[i];

        if (c == '\n') { line++; i++; continue; }
        if (std::isspace(static_cast<unsigned char>(c))) { i++; continue; }

        if (c == '/' && i + 1 < n && source[i + 1] == '/')
        {
            while (i < n && source[i] != '\n') i++;
            continue;
        }

        if (c == '"')
        {
            // Строковый литерал - только для print_str. Без escape-
            // последовательностей в v1 (\n и т.п. не нужны - Text VRAM
            // не понимает перевод строки как управляющий символ,
            // печать многострочного текста делается отдельными
            // вызовами print_str на разные y).
            size_t start = i + 1;
            i++;
            while (i < n && source[i] != '"' && source[i] != '\n') i++;
            if (i >= n || source[i] != '"')
            {
                throw std::runtime_error(
                    "Мини-C: строка " + std::to_string(line) +
                    ": незакрытый строковый литерал");
            }
            std::string text = source.substr(start, i - start);
            i++; // закрывающая "
            tokens.push_back({ TokType::STRING, text, 0, line });
            continue;
        }

        if (std::isdigit(static_cast<unsigned char>(c)))
        {
            size_t start = i;
            if (c == '0' && i + 1 < n && (source[i + 1] == 'x' || source[i + 1] == 'X'))
            {
                i += 2;
                while (i < n && std::isxdigit(static_cast<unsigned char>(source[i]))) i++;
                std::string text = source.substr(start, i - start);
                // stoull, не stol/stoi - адреса устройств вроде 0xF0000FE9
                // превышают диапазон 32-битного signed long (см. такой же
                // приём в Assembler::parseNumber).
                long long value = static_cast<long long>(std::stoull(text.substr(2), nullptr, 16));
                tokens.push_back({ TokType::NUMBER, text, value, line });
            }
            else
            {
                while (i < n && std::isdigit(static_cast<unsigned char>(source[i]))) i++;
                std::string text = source.substr(start, i - start);
                long long value = static_cast<long long>(std::stoull(text));
                tokens.push_back({ TokType::NUMBER, text, value, line });
            }
            continue;
        }

        if (std::isalpha(static_cast<unsigned char>(c)) || c == '_')
        {
            size_t start = i;
            while (i < n && (std::isalnum(static_cast<unsigned char>(source[i])) || source[i] == '_')) i++;
            std::string text = source.substr(start, i - start);
            bool isKeyword = false;
            for (const char* kw : keywords)
            {
                if (text == kw) { isKeyword = true; break; }
            }
            tokens.push_back({ isKeyword ? TokType::KEYWORD : TokType::IDENT, text, 0, line });
            continue;
        }

        // Многосимвольные операторы (максимальное совпадение).
        static const char* twoChar[] = {
            "==", "!=", "<=", ">=", "&&", "||", "<<", ">>"
        };
        bool matchedTwo = false;
        if (i + 1 < n)
        {
            std::string two = source.substr(i, 2);
            for (const char* op : twoChar)
            {
                if (two == op)
                {
                    tokens.push_back({ TokType::PUNCT, two, 0, line });
                    i += 2;
                    matchedTwo = true;
                    break;
                }
            }
        }
        if (matchedTwo) continue;

        static const std::string oneChar = "+-*/%&|^~!<>=(){}[],;";
        if (oneChar.find(c) != std::string::npos)
        {
            tokens.push_back({ TokType::PUNCT, std::string(1, c), 0, line });
            i++;
            continue;
        }

        throw std::runtime_error(
            "Мини-C: строка " + std::to_string(line) +
            ": неожиданный символ '" + std::string(1, c) + "'");
    }
}

const Compiler::Token& Compiler::peek() const
{
    return tokens[pos];
}

const Compiler::Token& Compiler::advance()
{
    const Token& t = tokens[pos];
    if (pos + 1 < tokens.size()) pos++;
    return t;
}

bool Compiler::check(const std::string& text) const
{
    return peek().text == text &&
        (peek().type == TokType::PUNCT || peek().type == TokType::KEYWORD);
}

bool Compiler::match(const std::string& text)
{
    if (check(text)) { advance(); return true; }
    return false;
}

const Compiler::Token& Compiler::expect(const std::string& text)
{
    if (!check(text))
    {
        error("ожидалось '" + text + "', встречено '" + peek().text + "'");
    }
    return advance();
}

const Compiler::Token& Compiler::expectIdent()
{
    if (peek().type != TokType::IDENT)
    {
        error("ожидался идентификатор, встречено '" + peek().text + "'");
    }
    return advance();
}

void Compiler::error(const std::string& message) const
{
    throw std::runtime_error(
        "Мини-C: строка " + std::to_string(peek().line) + ": " + message);
}

Compiler::NodePtr Compiler::node(NodeKind kind)
{
    auto n = std::make_shared<Node>();
    n->kind = kind;
    n->line = peek().line;
    return n;
}

// ---------------- Парсер ----------------

Compiler::NodePtr Compiler::parseProgram()
{
    auto prog = node(NodeKind::Program);
    while (peek().type != TokType::END)
    {
        prog->children.push_back(parseTopLevelDecl());
    }
    return prog;
}

Compiler::NodePtr Compiler::parseTopLevelDecl()
{
    if (match("const"))
    {
        auto n = node(NodeKind::ConstDecl);
        n->text = expectIdent().text;
        expect("=");
        n->children.push_back(parseExpr());
        expect(";");
        return n;
    }

    expect("int");
    std::string name = expectIdent().text;

    if (check("("))
    {
        return parseFuncDecl(name);
    }

    if (match("["))
    {
        auto n = node(NodeKind::ArrayDecl);
        n->text = name;
        NodePtr sizeExpr = parseExpr();
        n->children.push_back(sizeExpr);
        expect("]");
        if (match("="))
        {
            // Маппированный массив - "= адрес" вместо обычного DB-
            // хранилища привязывает arr[i] к готовому MMIO-адресу
            // (например, Text VRAM) - см. Compiler.h и ASSEMBLY.md,
            // "Мини-C". Адрес - константа времени компиляции, как у
            // poke/peek.
            n->children.push_back(parseExpr());
        }
        expect(";");
        return n;
    }

    auto n = node(NodeKind::VarDecl);
    n->text = name;
    if (match("="))
    {
        n->children.push_back(parseExpr());
    }
    expect(";");
    return n;
}

Compiler::NodePtr Compiler::parseFuncDecl(const std::string& name)
{
    auto n = node(NodeKind::FuncDecl);
    n->text = name;
    expect("(");
    if (!check(")"))
    {
        do
        {
            expect("int");
            auto p = node(NodeKind::Param);
            p->text = expectIdent().text;
            n->children.push_back(p);
        } while (match(","));
    }
    expect(")");
    n->children.push_back(parseBlock());
    return n;
}

Compiler::NodePtr Compiler::parseBlock()
{
    auto n = node(NodeKind::Block);
    expect("{");
    while (!check("}"))
    {
        n->children.push_back(parseStatement());
    }
    expect("}");
    return n;
}

Compiler::NodePtr Compiler::parseVarDeclStatement()
{
    expect("int");
    auto n = node(NodeKind::VarDecl);
    n->text = expectIdent().text;
    if (match("="))
    {
        n->children.push_back(parseExpr());
    }
    expect(";");
    return n;
}

Compiler::NodePtr Compiler::parseExprStatement()
{
    auto n = node(NodeKind::ExprStmt);
    n->children.push_back(parseExpr());
    expect(";");
    return n;
}

Compiler::NodePtr Compiler::parseStatement()
{
    if (check("int")) return parseVarDeclStatement();
    if (check("{")) return parseBlock();

    if (match("if"))
    {
        auto n = node(NodeKind::If);
        expect("(");
        n->children.push_back(parseExpr());
        expect(")");
        n->children.push_back(parseStatement());
        if (match("else"))
        {
            n->children.push_back(parseStatement());
        }
        return n;
    }

    if (match("while"))
    {
        auto n = node(NodeKind::While);
        expect("(");
        n->children.push_back(parseExpr());
        expect(")");
        n->children.push_back(parseStatement());
        return n;
    }

    if (match("for"))
    {
        auto n = node(NodeKind::For);
        expect("(");
        n->children.push_back(parseExpr());   // init (присваивание)
        expect(";");
        n->children.push_back(parseExpr());   // условие
        expect(";");
        n->children.push_back(parseExpr());   // post (присваивание)
        expect(")");
        n->children.push_back(parseStatement());
        return n;
    }

    if (match("return"))
    {
        auto n = node(NodeKind::Return);
        if (!check(";"))
        {
            n->children.push_back(parseExpr());
        }
        expect(";");
        return n;
    }

    return parseExprStatement();
}

Compiler::NodePtr Compiler::parseExpr()
{
    return parseAssignment();
}

Compiler::NodePtr Compiler::parseAssignment()
{
    NodePtr left = parseLogicalOr();
    if (match("="))
    {
        NodePtr value = parseAssignment();
        if (left->kind == NodeKind::Ident)
        {
            auto n = node(NodeKind::Assign);
            n->text = left->text;
            n->children.push_back(value);
            return n;
        }
        if (left->kind == NodeKind::Index)
        {
            auto n = node(NodeKind::IndexAssign);
            n->text = left->text;
            n->children.push_back(left->children[0]);   // индекс
            n->children.push_back(value);
            return n;
        }
        error("в левой части присваивания должна быть переменная или элемент массива");
    }
    return left;
}

Compiler::NodePtr Compiler::parseLogicalOr()
{
    NodePtr left = parseLogicalAnd();
    while (match("||"))
    {
        auto n = node(NodeKind::LogicalOr);
        n->children.push_back(left);
        n->children.push_back(parseLogicalAnd());
        left = n;
    }
    return left;
}

Compiler::NodePtr Compiler::parseLogicalAnd()
{
    NodePtr left = parseEquality();
    while (match("&&"))
    {
        auto n = node(NodeKind::LogicalAnd);
        n->children.push_back(left);
        n->children.push_back(parseEquality());
        left = n;
    }
    return left;
}

Compiler::NodePtr Compiler::parseEquality()
{
    NodePtr left = parseRelational();
    while (check("==") || check("!="))
    {
        std::string op = advance().text;
        auto n = node(NodeKind::BinOp);
        n->text = op;
        n->children.push_back(left);
        n->children.push_back(parseRelational());
        left = n;
    }
    return left;
}

Compiler::NodePtr Compiler::parseRelational()
{
    NodePtr left = parseBitwiseOr();
    while (check("<") || check(">") || check("<=") || check(">="))
    {
        std::string op = advance().text;
        auto n = node(NodeKind::BinOp);
        n->text = op;
        n->children.push_back(left);
        n->children.push_back(parseBitwiseOr());
        left = n;
    }
    return left;
}

Compiler::NodePtr Compiler::parseBitwiseOr()
{
    NodePtr left = parseBitwiseXor();
    while (check("|"))
    {
        advance();
        auto n = node(NodeKind::BinOp);
        n->text = "|";
        n->children.push_back(left);
        n->children.push_back(parseBitwiseXor());
        left = n;
    }
    return left;
}

Compiler::NodePtr Compiler::parseBitwiseXor()
{
    NodePtr left = parseBitwiseAnd();
    while (check("^"))
    {
        advance();
        auto n = node(NodeKind::BinOp);
        n->text = "^";
        n->children.push_back(left);
        n->children.push_back(parseBitwiseAnd());
        left = n;
    }
    return left;
}

Compiler::NodePtr Compiler::parseBitwiseAnd()
{
    NodePtr left = parseShift();
    while (check("&"))
    {
        advance();
        auto n = node(NodeKind::BinOp);
        n->text = "&";
        n->children.push_back(left);
        n->children.push_back(parseShift());
        left = n;
    }
    return left;
}

Compiler::NodePtr Compiler::parseShift()
{
    NodePtr left = parseAdditive();
    while (check("<<") || check(">>"))
    {
        std::string op = advance().text;
        auto n = node(NodeKind::BinOp);
        n->text = op;
        n->children.push_back(left);
        n->children.push_back(parseAdditive());
        left = n;
    }
    return left;
}

Compiler::NodePtr Compiler::parseAdditive()
{
    NodePtr left = parseMultiplicative();
    while (check("+") || check("-"))
    {
        std::string op = advance().text;
        auto n = node(NodeKind::BinOp);
        n->text = op;
        n->children.push_back(left);
        n->children.push_back(parseMultiplicative());
        left = n;
    }
    return left;
}

Compiler::NodePtr Compiler::parseMultiplicative()
{
    NodePtr left = parseUnary();
    while (check("*") || check("/") || check("%"))
    {
        std::string op = advance().text;
        auto n = node(NodeKind::BinOp);
        n->text = op;
        n->children.push_back(left);
        n->children.push_back(parseUnary());
        left = n;
    }
    return left;
}

Compiler::NodePtr Compiler::parseUnary()
{
    if (check("-") || check("~") || check("!"))
    {
        std::string op = advance().text;
        auto n = node(NodeKind::UnaryOp);
        n->text = op;
        n->children.push_back(parseUnary());
        return n;
    }
    return parsePrimary();
}

Compiler::NodePtr Compiler::parsePrimary()
{
    if (peek().type == TokType::NUMBER)
    {
        auto n = node(NodeKind::Number);
        n->value = advance().value;
        return n;
    }

    if (match("("))
    {
        NodePtr n = parseExpr();
        expect(")");
        return n;
    }

    if (check("peek") && peek().type == TokType::KEYWORD)
    {
        advance();
        auto n = node(NodeKind::Peek);
        expect("(");
        n->children.push_back(parseExpr());
        expect(")");
        return n;
    }

    if (check("poke") && peek().type == TokType::KEYWORD)
    {
        advance();
        auto n = node(NodeKind::Poke);
        expect("(");
        n->children.push_back(parseExpr());
        expect(",");
        n->children.push_back(parseExpr());
        expect(")");
        return n;
    }

    if (check("print_char") && peek().type == TokType::KEYWORD)
    {
        advance();
        auto n = node(NodeKind::PrintChar);
        expect("(");
        n->children.push_back(parseExpr());   // x
        expect(",");
        n->children.push_back(parseExpr());   // y
        expect(",");
        n->children.push_back(parseExpr());   // ch
        expect(")");
        return n;
    }

    if (check("print_str") && peek().type == TokType::KEYWORD)
    {
        advance();
        auto n = node(NodeKind::PrintStr);
        expect("(");
        n->children.push_back(parseExpr());   // x
        expect(",");
        n->children.push_back(parseExpr());   // y
        expect(",");
        if (peek().type != TokType::STRING)
        {
            error("print_str ожидает строковый литерал третьим аргументом");
        }
        n->text = advance().text;             // сама строка
        expect(")");
        return n;
    }

    if (check("set_color") && peek().type == TokType::KEYWORD)
    {
        advance();
        auto n = node(NodeKind::SetColor);
        expect("(");
        n->children.push_back(parseExpr());   // x
        expect(",");
        n->children.push_back(parseExpr());   // y
        expect(",");
        n->children.push_back(parseExpr());   // fg
        expect(",");
        n->children.push_back(parseExpr());   // bg
        expect(")");
        return n;
    }

    if (check("clear_screen") && peek().type == TokType::KEYWORD)
    {
        advance();
        auto n = node(NodeKind::ClearScreen);
        expect("(");
        expect(")");
        return n;
    }

    if (check("exec_child") && peek().type == TokType::KEYWORD)
    {
        advance();
        auto n = node(NodeKind::ExecChild);
        expect("(");
        expect(")");
        return n;
    }

    if (check("mod_load") && peek().type == TokType::KEYWORD)
    {
        advance();
        auto n = node(NodeKind::ModLoad);
        expect("(");
        if (peek().type != TokType::STRING)
        {
            error("mod_load ожидает строковый литерал (имя файла)");
        }
        n->text = advance().text;             // имя .mod-файла
        expect(")");
        return n;
    }

    if (check("str_copy") && peek().type == TokType::KEYWORD)
    {
        advance();
        auto n = node(NodeKind::StrCopy);
        expect("(");
        const Token& identTok = expectIdent();   // имя мапированного массива - резолвится в кодогене, а не как рантайм-выражение
        auto arrNode = node(NodeKind::Ident);
        arrNode->text = identTok.text;
        n->children.push_back(arrNode);
        expect(",");
        if (peek().type != TokType::STRING)
        {
            error("str_copy ожидает строковый литерал вторым аргументом");
        }
        n->text = advance().text;             // сама строка
        expect(")");
        return n;
    }

    if (check("sound_play") && peek().type == TokType::KEYWORD)
    {
        advance();
        auto n = node(NodeKind::SoundPlay);
        expect("(");
        expect(")");
        return n;
    }

    if (check("sound_stop") && peek().type == TokType::KEYWORD)
    {
        advance();
        auto n = node(NodeKind::SoundStop);
        expect("(");
        expect(")");
        return n;
    }

    if (check("sound_pause") && peek().type == TokType::KEYWORD)
    {
        advance();
        auto n = node(NodeKind::SoundPause);
        expect("(");
        expect(")");
        return n;
    }

    if (check("sound_resume") && peek().type == TokType::KEYWORD)
    {
        advance();
        auto n = node(NodeKind::SoundResume);
        expect("(");
        expect(")");
        return n;
    }

    if (check("sound_set_volume") && peek().type == TokType::KEYWORD)
    {
        advance();
        auto n = node(NodeKind::SoundSetVolume);
        expect("(");
        n->children.push_back(parseExpr());   // volume
        expect(")");
        return n;
    }

    if (peek().type == TokType::IDENT)
    {
        std::string name = advance().text;

        if (match("("))
        {
            auto n = node(NodeKind::Call);
            n->text = name;
            if (!check(")"))
            {
                do
                {
                    n->children.push_back(parseExpr());
                } while (match(","));
            }
            expect(")");
            return n;
        }

        if (match("["))
        {
            auto n = node(NodeKind::Index);
            n->text = name;
            n->children.push_back(parseExpr());
            expect("]");
            return n;
        }

        auto n = node(NodeKind::Ident);
        n->text = name;
        return n;
    }

    error("ожидалось выражение, встречено '" + peek().text + "'");
}

// ---------------- Семантика ----------------

long long Compiler::foldConst(const NodePtr& expr) const
{
    switch (expr->kind)
    {
    case NodeKind::Number:
        return expr->value;

    case NodeKind::Ident:
    {
        auto it = constants.find(expr->text);
        if (it == constants.end())
        {
            throw std::runtime_error(
                "Мини-C: строка " + std::to_string(expr->line) +
                ": '" + expr->text + "' не является константой времени компиляции");
        }
        return it->second;
    }

    case NodeKind::UnaryOp:
    {
        // Без маски & 0xFF - foldConst используется только для адресов
        // poke/peek, значений const и размеров массивов, а не для
        // рантайм-арифметики над int (та заворачивается сама, в железе,
        // через реальные 8-битные опкоды CPU - см. genExprToA). Адреса
        // устройств (0xF0000007 и т.п.) не помещаются в один байт, и
        // маска их бы попросту обрезала.
        long long v = foldConst(expr->children[0]);
        if (expr->text == "-") return -v;
        if (expr->text == "~") return ~v;
        if (expr->text == "!") return v == 0 ? 1 : 0;
        break;
    }

    case NodeKind::BinOp:
    {
        long long a = foldConst(expr->children[0]);
        long long b = foldConst(expr->children[1]);
        const std::string& op = expr->text;
        if (op == "+") return a + b;
        if (op == "-") return a - b;
        if (op == "*") return a * b;
        if (op == "/") return b == 0 ? a : a / b;
        if (op == "%") return b == 0 ? a : a % b;
        if (op == "&") return a & b;
        if (op == "|") return a | b;
        if (op == "^") return a ^ b;
        if (op == "<<") return a << b;
        if (op == ">>") return a >> b;
        break;
    }

    default:
        break;
    }

    throw std::runtime_error(
        "Мини-C: строка " + std::to_string(expr->line) +
        ": выражение не является константой времени компиляции");
}

void Compiler::collectVarDecls(const NodePtr& n)
{
    if (!n) return;

    if (n->kind == NodeKind::VarDecl)
    {
        bool seen = false;
        for (const auto& name : globalVars)
        {
            if (name == n->text) { seen = true; break; }
        }
        if (!seen) globalVars.push_back(n->text);
    }

    for (const auto& child : n->children)
    {
        collectVarDecls(child);
    }
}

void Compiler::collectDeclarations(const NodePtr& program)
{
    for (const auto& decl : program->children)
    {
        if (decl->kind == NodeKind::ConstDecl)
        {
            constants[decl->text] = foldConst(decl->children[0]);
        }
        else if (decl->kind == NodeKind::ArrayDecl)
        {
            arraySizes[decl->text] = static_cast<int>(foldConst(decl->children[0]));
            if (decl->children.size() > 1)
            {
                arrayBaseAddr[decl->text] = foldConst(decl->children[1]);
            }
        }
        else if (decl->kind == NodeKind::FuncDecl)
        {
            FunctionInfo info;
            for (size_t i = 0; i + 1 < decl->children.size(); i++)
            {
                info.paramGlobals.push_back(decl->children[i]->text);
            }
            functions[decl->text] = info;
        }
    }

    // `int x;` внутри тела функции - не настоящая локальная переменная
    // (см. Compiler.h) - под неё тоже нужна глобальная DB-ячейка, как
    // и для `int x;` верхнего уровня, поэтому ищем ВСЕ VarDecl во всём
    // дереве, а не только среди прямых детей Program.
    collectVarDecls(program);
}

// ---------------- Кодоген ----------------

std::string Compiler::newLabel(const std::string& hint)
{
    return "__mc_" + hint + "_" + std::to_string(labelCounter++);
}

std::string Compiler::mangleParam(const std::string& func, const std::string& param) const
{
    return func + "__" + param;
}

void Compiler::genComparisonToA(const NodePtr& expr)
{
    // Результат сравнения материализуется как 0/1 в A - см.
    // Compiler.h, комментарий про "простой, единообразный" подход.
    const std::string& op = expr->text;

    genExprToA(expr->children[1]);
    *codeOut << "    PUSH A\n";
    genExprToA(expr->children[0]);
    *codeOut << "    POP B\n";
    *codeOut << "    CMP B\n";

    std::string trueLabel = newLabel("cmp_true");
    std::string endLabel = newLabel("cmp_end");

    if (op == "==") *codeOut << "    JZ " << trueLabel << "\n";
    else if (op == "!=") *codeOut << "    JNZ " << trueLabel << "\n";
    else if (op == "<") *codeOut << "    JC " << trueLabel << "\n";
    else if (op == ">=") *codeOut << "    JNC " << trueLabel << "\n";
    else if (op == ">")
    {
        // A > B  <=>  не(A < B) и не(A == B)
        *codeOut << "    JC " << endLabel << "_false\n";
        *codeOut << "    JZ " << endLabel << "_false\n";
        *codeOut << "    JMP " << trueLabel << "\n";
        *codeOut << endLabel << "_false:\n";
        *codeOut << "    LDI A, 0\n";
        *codeOut << "    JMP " << endLabel << "\n";
        *codeOut << trueLabel << ":\n";
        *codeOut << "    LDI A, 1\n";
        *codeOut << endLabel << ":\n";
        return;
    }
    else if (op == "<=")
    {
        // A <= B  <=>  (A < B) или (A == B)
        *codeOut << "    JC " << trueLabel << "\n";
        *codeOut << "    JZ " << trueLabel << "\n";
        *codeOut << "    LDI A, 0\n";
        *codeOut << "    JMP " << endLabel << "\n";
        *codeOut << trueLabel << ":\n";
        *codeOut << "    LDI A, 1\n";
        *codeOut << endLabel << ":\n";
        return;
    }

    *codeOut << "    LDI A, 0\n";
    *codeOut << "    JMP " << endLabel << "\n";
    *codeOut << trueLabel << ":\n";
    *codeOut << "    LDI A, 1\n";
    *codeOut << endLabel << ":\n";
}

void Compiler::genAddressOf(const NodePtr& indexNode)
{
    auto it = arraySizes.find(indexNode->text);
    if (it == arraySizes.end())
    {
        throw std::runtime_error(
            "Мини-C: строка " + std::to_string(indexNode->line) +
            ": '" + indexNode->text + "' не является массивом");
    }

    auto mapped = arrayBaseAddr.find(indexNode->text);
    if (mapped != arrayBaseAddr.end())
    {
        *codeOut << "    LDHL " << mapped->second << "\n";
    }
    else
    {
        *codeOut << "    LDHL " << indexNode->text << "\n";
    }
    genExprToA(indexNode->children[0]);
    *codeOut << "    CALL __mc_hladd\n";
}

void Compiler::genScreenAddress(long long base, const NodePtr& xExpr, const NodePtr& yExpr)
{
    // HL = base + y*80 + x. y*80 НЕЛЬЗЯ считать через один 8-битный MUL
    // - для 80x25 экрана y доходит до 24, 24*80=1920, тихо завернулся
    // бы. __mc_screen_offset копит y*80+x как настоящую 16-битную пару
    // байт (ADD/ADC - перенос между байтами) и одним ADDHL прибавляет
    // результат к HL за один шаг (см. CPU.h/ASSEMBLY.md, ADDHL) - x
    // передаётся через __mc_scr_x и учитывается внутри самого
    // __mc_screen_offset, отдельного вызова __mc_hladd для x больше
    // не нужно.
    usesScreenHelper = true;

    genExprToA(yExpr);
    *codeOut << "    STA __mc_scr_y\n";
    genExprToA(xExpr);
    *codeOut << "    STA __mc_scr_x\n";

    *codeOut << "    LDHL " << base << "\n";
    *codeOut << "    LDA __mc_scr_y\n";
    *codeOut << "    CALL __mc_screen_offset\n";
}

void Compiler::genPrintChar(const NodePtr& expr)
{
    // ch считаем ДО genScreenAddress - тот в процессе вычисления x/y
    // свободно использует A/B/C, ch должен пережить это в памяти, не
    // в регистре.
    genExprToA(expr->children[2]);
    *codeOut << "    STA __mc_pc_ch\n";

    genScreenAddress(0xF0000007, expr->children[0], expr->children[1]);

    *codeOut << "    LDA __mc_pc_ch\n";
    *codeOut << "    STX\n";
}

void Compiler::genSetColor(const NodePtr& expr)
{
    // Байт атрибута TextAttr - fg в младшем полубайте, bg в старшем
    // (см. ASSEMBLY.md, "TextAttr"): attr = fg | (bg << 4) = fg + bg*16.
    genExprToA(expr->children[3]);   // bg
    *codeOut << "    STA __mc_sc_bg\n";
    genExprToA(expr->children[2]);   // fg
    *codeOut << "    STA __mc_sc_fg\n";

    genScreenAddress(0xF000080C, expr->children[0], expr->children[1]);

    *codeOut << "    LDA __mc_sc_bg\n";
    *codeOut << "    LDI B, 16\n";
    *codeOut << "    MUL B\n";
    *codeOut << "    PUSH A\n";
    *codeOut << "    LDA __mc_sc_fg\n";
    *codeOut << "    POP B\n";
    *codeOut << "    ADD B\n";
    *codeOut << "    STX\n";
}

void Compiler::genPrintStr(const NodePtr& expr)
{
    usesScreenHelper = true;

    const std::string& text = expr->text;
    std::string strLabel = newLabel("str");
    std::string loopLabel = newLabel("ps_loop");
    std::string doneLabel = newLabel("ps_done");

    // Байты строки - как обычный маленький массив (DB-данные), только
    // без счёта в arraySizes - индексируется точно так же, вручную,
    // через __mc_hladd.
    *dataOut << strLabel << ": DB "
        << (text.empty() ? 0 : static_cast<int>(static_cast<unsigned char>(text[0]))) << "\n";
    for (size_t i = 1; i < text.size(); i++)
    {
        *dataOut << "    DB " << static_cast<int>(static_cast<unsigned char>(text[i])) << "\n";
    }

    genExprToA(expr->children[1]);   // y - не меняется на всю строку
    *codeOut << "    STA __mc_ps_y\n";
    genExprToA(expr->children[0]);   // x - стартовая колонка
    *codeOut << "    STA __mc_ps_x\n";

    *codeOut << "    LDI A, 0\n";
    *codeOut << "    STA __mc_ps_i\n";

    *codeOut << loopLabel << ":\n";
    *codeOut << "    LDA __mc_ps_i\n";
    *codeOut << "    LDI B, " << text.size() << "\n";
    *codeOut << "    CMP B\n";
    *codeOut << "    JZ " << doneLabel << "\n";

    *codeOut << "    LDHL " << strLabel << "\n";
    *codeOut << "    LDA __mc_ps_i\n";
    *codeOut << "    CALL __mc_hladd\n";
    *codeOut << "    LDX\n";
    *codeOut << "    STA __mc_ps_ch\n";

    // __mc_screen_offset теперь сама добавляет и y*80, и x (через
    // __mc_scr_x) - считаем текущую колонку (x+i) и кладём именно
    // туда перед вызовом (это её контракт, см. genScreenAddress).
    *codeOut << "    LDA __mc_ps_x\n";
    *codeOut << "    PUSH A\n";
    *codeOut << "    LDA __mc_ps_i\n";
    *codeOut << "    POP B\n";
    *codeOut << "    ADD B\n";
    *codeOut << "    STA __mc_scr_x\n";

    *codeOut << "    LDHL 0xF0000007\n";
    *codeOut << "    LDA __mc_ps_y\n";
    *codeOut << "    CALL __mc_screen_offset\n";

    *codeOut << "    LDA __mc_ps_ch\n";
    *codeOut << "    STX\n";

    *codeOut << "    LDA __mc_ps_i\n";
    *codeOut << "    LDI B, 1\n";
    *codeOut << "    ADD B\n";
    *codeOut << "    STA __mc_ps_i\n";
    *codeOut << "    JMP " << loopLabel << "\n";

    *codeOut << doneLabel << ":\n";
}

void Compiler::genModLoad(const NodePtr& expr)
{
    // В отличие от print_str, адрес назначения тут ВСЕГДА фиксирован
    // (NAME0-31 у ModLoader, 0xF0001020-0xF000103F) - рантайм-цикл не
    // нужен вообще, компилятор просто разворачивает запись имени файла
    // в плоскую последовательность LDI+STA по одному байту на символ,
    // прямо на этапе компиляции (см. ASSEMBLY.md, "mod_load"). Итоговое
    // значение выражения - STATUS после LOAD (0=ok,1=не найден,
    // 2=формат,3=битый) - остаётся в A, как и положено genExprToA.

    const std::string& text = expr->text;

    if (text.size() > 32)
    {
        throw std::runtime_error(
            "Мини-C: mod_load - имя файла длиннее 32 символов: \"" + text + "\"");
    }

    const uint32_t nameBase = 0xF0001020;

    for (size_t i = 0; i < text.size(); i++)
    {
        *codeOut << "    LDI A, " << static_cast<int>(static_cast<unsigned char>(text[i])) << "\n";
        *codeOut << "    STA " << (nameBase + i) << "\n";
    }
    for (size_t i = text.size(); i < 32; i++)
    {
        *codeOut << "    LDI A, 0\n";
        *codeOut << "    STA " << (nameBase + i) << "\n";
    }

    *codeOut << "    LDI A, 1\n";
    *codeOut << "    STA 0xF0001040\n";   // ModLoader COMMAND = LOAD
    *codeOut << "    LDA 0xF0001041\n";   // ModLoader STATUS - остаётся в A
}

void Compiler::genStrCopy(const NodePtr& expr)
{
    // Тот же приём, что genModLoad выше, но обобщённый на произвольный
    // мапированный массив: адрес и предел длины берутся из arrayBaseAddr/
    // arraySizes (заполняются в collectDeclarations из "int arr[N] =
    // адрес;") вместо жёстко зашитых constant/32. В отличие от mod_load,
    // str_copy НЕ триггерит команду устройства - это отдельный шаг
    // (poke(..._COMMAND, 1)), который пользователь делает сам, поэтому
    // итоговое значение выражения - просто 0.

    const std::string& arrName = expr->children[0]->text;
    const std::string& text = expr->text;

    auto sizeIt = arraySizes.find(arrName);
    if (sizeIt == arraySizes.end())
    {
        throw std::runtime_error(
            "Мини-C: строка " + std::to_string(expr->line) +
            ": str_copy - '" + arrName + "' не является массивом");
    }
    auto baseIt = arrayBaseAddr.find(arrName);
    if (baseIt == arrayBaseAddr.end())
    {
        throw std::runtime_error(
            "Мини-C: строка " + std::to_string(expr->line) +
            ": str_copy - '" + arrName + "' не мапирован на адрес устройства (нужен 'int " +
            arrName + "[N] = 0xADDR;')");
    }

    int size = sizeIt->second;
    long long base = baseIt->second;

    if (static_cast<int>(text.size()) > size)
    {
        throw std::runtime_error(
            "Мини-C: строка " + std::to_string(expr->line) +
            ": str_copy - строка \"" + text + "\" (" + std::to_string(text.size()) +
            " симв.) длиннее массива '" + arrName + "' (" + std::to_string(size) + ")");
    }

    for (size_t i = 0; i < text.size(); i++)
    {
        *codeOut << "    LDI A, " << static_cast<int>(static_cast<unsigned char>(text[i])) << "\n";
        *codeOut << "    STA " << (base + i) << "\n";
    }
    for (int i = static_cast<int>(text.size()); i < size; i++)
    {
        *codeOut << "    LDI A, 0\n";
        *codeOut << "    STA " << (base + i) << "\n";
    }

    *codeOut << "    LDI A, 0\n";
}

void Compiler::genExprToA(const NodePtr& expr)
{
    switch (expr->kind)
    {
    case NodeKind::Number:
        *codeOut << "    LDI A, " << expr->value << "\n";
        return;

    case NodeKind::Assign:
    {
        genExprToA(expr->children[0]);
        if (!currentFunction.empty())
        {
            const auto& params = functions[currentFunction].paramGlobals;
            bool isParam = false;
            for (const auto& p : params)
            {
                if (p == expr->text)
                {
                    *codeOut << "    STA " << mangleParam(currentFunction, expr->text) << "\n";
                    isParam = true;
                    break;
                }
            }
            if (isParam) return;
        }
        *codeOut << "    STA " << expr->text << "\n";
        return;
    }

    case NodeKind::IndexAssign:
    {
        auto indexNode = std::make_shared<Node>();
        indexNode->kind = NodeKind::Index;
        indexNode->text = expr->text;
        indexNode->line = expr->line;
        indexNode->children.push_back(expr->children[0]);

        genExprToA(expr->children[1]);
        *codeOut << "    PUSH A\n";
        genAddressOf(indexNode);
        *codeOut << "    POP A\n";
        *codeOut << "    STX\n";
        return;
    }

    case NodeKind::Ident:
    {
        std::string name = expr->text;
        auto constIt = constants.find(name);
        if (constIt != constants.end())
        {
            *codeOut << "    LDI A, " << constIt->second << "\n";
            return;
        }
        if (!currentFunction.empty())
        {
            const auto& params = functions[currentFunction].paramGlobals;
            for (const auto& p : params)
            {
                if (p == name)
                {
                    *codeOut << "    LDA " << mangleParam(currentFunction, name) << "\n";
                    return;
                }
            }
        }
        *codeOut << "    LDA " << name << "\n";
        return;
    }

    case NodeKind::Index:
        genAddressOf(expr);
        *codeOut << "    LDX\n";
        return;

    case NodeKind::Peek:
    {
        long long addr = foldConst(expr->children[0]);
        *codeOut << "    LDA " << addr << "\n";
        return;
    }

    case NodeKind::Poke:
    {
        long long addr = foldConst(expr->children[0]);
        genExprToA(expr->children[1]);
        *codeOut << "    STA " << addr << "\n";
        return;
    }

    case NodeKind::PrintChar:
        genPrintChar(expr);
        return;

    case NodeKind::PrintStr:
        genPrintStr(expr);
        return;

    case NodeKind::SetColor:
        genSetColor(expr);
        return;

    case NodeKind::ClearScreen:
        // CLEAR у Text VRAM (0xF00007D8) и TextAttr (0xF0000FDD) -
        // готовые регистры устройств (см. ASSEMBLY.md, "Text VRAM"/
        // "TextAttr") - "очистить экран" для пользователя мини-C
        // естественно значит и то, и другое сразу (иначе после
        // очистки старые цвета "просвечивали" бы сквозь пробелы).
        *codeOut << "    LDI A, 1\n";
        *codeOut << "    STA 0xF00007D8\n";
        *codeOut << "    STA 0xF0000FDD\n";
        return;

    case NodeKind::ExecChild:
        // Запуск дочерней программы - НЕ напрямую в песочницу, а через
        // системный вызов резидентного SHELL.ASM: фиксированная точка
        // входа 0x0000000A (shell_exec_child), запатченная SHELL.ASM
        // при старте (тем же способом, что и вектор прерывания
        // 0x00000005 - см. SHELL.ASM::main). Именно shell_exec_child
        // решает, по какому адресу и какой командой диска грузить
        // дочернюю программу (см. Disk.h, EXEC_CHILD_DEPTHn_ADDRESS) -
        // компилятору эти детали знать не нужно, они могут меняться
        // независимо (например, при добавлении ещё одного уровня
        // вложенности). Перед вызовом вызывающая программа должна
        // указать диск с именем запускаемого файла через
        // poke(EXEC_CHILD_DISK, diskId) - см. ASSEMBLY.md, "exec_child".
        // Управление вернётся сюда же, когда дочерняя программа дойдёт
        // до своего RET (см. genFunction() - любая функция Мини-C,
        // включая main(), гарантированно заканчивается RET, не HLT).
        *codeOut << "    CALL 0x0000000A\n";
        return;

    case NodeKind::ModLoad:
        genModLoad(expr);
        return;

    case NodeKind::StrCopy:
        genStrCopy(expr);
        return;

    case NodeKind::SoundPlay:
        *codeOut << "    LDI A, 1\n";
        *codeOut << "    STA 0xF0001066\n";   // SoundCard COMMAND = PLAY
        return;

    case NodeKind::SoundStop:
        *codeOut << "    LDI A, 2\n";
        *codeOut << "    STA 0xF0001066\n";   // SoundCard COMMAND = STOP
        return;

    case NodeKind::SoundPause:
        *codeOut << "    LDI A, 3\n";
        *codeOut << "    STA 0xF0001066\n";   // SoundCard COMMAND = PAUSE
        return;

    case NodeKind::SoundResume:
        *codeOut << "    LDI A, 4\n";
        *codeOut << "    STA 0xF0001066\n";   // SoundCard COMMAND = RESUME
        return;

    case NodeKind::SoundSetVolume:
        genExprToA(expr->children[0]);
        *codeOut << "    STA 0xF0001068\n";   // SoundCard VOLUME
        return;

    case NodeKind::Call:
    {
        auto it = functions.find(expr->text);
        if (it == functions.end())
        {
            throw std::runtime_error(
                "Мини-C: строка " + std::to_string(expr->line) +
                ": вызов необъявленной функции '" + expr->text + "'");
        }
        if (it->second.paramGlobals.size() != expr->children.size())
        {
            throw std::runtime_error(
                "Мини-C: строка " + std::to_string(expr->line) +
                ": '" + expr->text + "' ожидает " +
                std::to_string(it->second.paramGlobals.size()) + " аргумент(ов)");
        }
        for (size_t i = 0; i < expr->children.size(); i++)
        {
            genExprToA(expr->children[i]);
            *codeOut << "    STA " << mangleParam(expr->text, it->second.paramGlobals[i]) << "\n";
        }
        *codeOut << "    CALL " << expr->text << "\n";
        return;
    }

    case NodeKind::UnaryOp:
    {
        if (expr->text == "~")
        {
            genExprToA(expr->children[0]);
            *codeOut << "    NOT\n";
            return;
        }
        if (expr->text == "-")
        {
            genExprToA(expr->children[0]);
            *codeOut << "    PUSH A\n";
            *codeOut << "    LDI A, 0\n";
            *codeOut << "    POP B\n";
            *codeOut << "    SUB B\n";
            return;
        }
        if (expr->text == "!")
        {
            genExprToA(expr->children[0]);
            *codeOut << "    PUSH A\n";
            *codeOut << "    POP B\n";
            *codeOut << "    LDI A, 0\n";
            *codeOut << "    CMP B\n";
            std::string trueLabel = newLabel("not_true");
            std::string endLabel = newLabel("not_end");
            *codeOut << "    JZ " << trueLabel << "\n";
            *codeOut << "    LDI A, 0\n";
            *codeOut << "    JMP " << endLabel << "\n";
            *codeOut << trueLabel << ":\n";
            *codeOut << "    LDI A, 1\n";
            *codeOut << endLabel << ":\n";
            return;
        }
        break;
    }

    case NodeKind::LogicalAnd:
    {
        std::string falseLabel = newLabel("and_false");
        std::string endLabel = newLabel("and_end");
        genCondition(expr->children[0], falseLabel);
        genCondition(expr->children[1], falseLabel);
        *codeOut << "    LDI A, 1\n";
        *codeOut << "    JMP " << endLabel << "\n";
        *codeOut << falseLabel << ":\n";
        *codeOut << "    LDI A, 0\n";
        *codeOut << endLabel << ":\n";
        return;
    }

    case NodeKind::LogicalOr:
    {
        std::string trueLabel = newLabel("or_true");
        std::string endLabel = newLabel("or_end");

        genExprToA(expr->children[0]);
        *codeOut << "    LDI B, 0\n";
        *codeOut << "    CMP B\n";
        *codeOut << "    JNZ " << trueLabel << "\n";

        genExprToA(expr->children[1]);
        *codeOut << "    LDI B, 0\n";
        *codeOut << "    CMP B\n";
        *codeOut << "    JNZ " << trueLabel << "\n";

        *codeOut << "    LDI A, 0\n";
        *codeOut << "    JMP " << endLabel << "\n";
        *codeOut << trueLabel << ":\n";
        *codeOut << "    LDI A, 1\n";
        *codeOut << endLabel << ":\n";
        return;
    }

    case NodeKind::BinOp:
    {
        const std::string& op = expr->text;
        if (op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=")
        {
            genComparisonToA(expr);
            return;
        }
        if (op == "<<" || op == ">>")
        {
            genExprToA(expr->children[1]);
            *codeOut << "    PUSH A\n";
            genExprToA(expr->children[0]);
            *codeOut << "    POP B\n";
            *codeOut << "    PUSH B\n";
            *codeOut << "    POP C\n";
            *codeOut << "    LDI D, 0\n";
            std::string loopLabel = newLabel("shift_loop");
            std::string endLabel = newLabel("shift_end");
            *codeOut << loopLabel << ":\n";
            *codeOut << "    PUSH A\n";
            *codeOut << "    PUSH C\n";
            *codeOut << "    POP A\n";
            *codeOut << "    CMP D\n";
            *codeOut << "    POP A\n";
            *codeOut << "    JZ " << endLabel << "\n";
            *codeOut << "    " << (op == "<<" ? "SHL" : "SHR") << "\n";
            *codeOut << "    PUSH A\n";
            *codeOut << "    PUSH C\n";
            *codeOut << "    POP A\n";
            *codeOut << "    LDI B, 1\n";
            *codeOut << "    SUB B\n";
            *codeOut << "    PUSH A\n";
            *codeOut << "    POP C\n";
            *codeOut << "    POP A\n";
            *codeOut << "    JMP " << loopLabel << "\n";
            *codeOut << endLabel << ":\n";
            return;
        }

        genExprToA(expr->children[1]);
        *codeOut << "    PUSH A\n";
        genExprToA(expr->children[0]);
        *codeOut << "    POP B\n";

        if (op == "+") *codeOut << "    ADD B\n";
        else if (op == "-") *codeOut << "    SUB B\n";
        else if (op == "*") *codeOut << "    MUL B\n";
        else if (op == "/") *codeOut << "    DIV B\n";
        else if (op == "%") *codeOut << "    MOD B\n";
        else if (op == "&") *codeOut << "    AND B\n";
        else if (op == "|") *codeOut << "    OR B\n";
        else if (op == "^") *codeOut << "    XOR B\n";
        return;
    }

    default:
        break;
    }

    throw std::runtime_error(
        "Мини-C: строка " + std::to_string(expr->line) + ": некорректное выражение");
}

void Compiler::genCondition(const NodePtr& expr, const std::string& falseLabel)
{
    genExprToA(expr);
    *codeOut << "    LDI B, 0\n";
    *codeOut << "    CMP B\n";
    *codeOut << "    JZ " << falseLabel << "\n";
}

void Compiler::genStatement(const NodePtr& stmt)
{
    switch (stmt->kind)
    {
    case NodeKind::Block:
        genBlock(stmt);
        return;

    case NodeKind::VarDecl:
        if (!stmt->children.empty())
        {
            genExprToA(stmt->children[0]);
            *codeOut << "    STA " << stmt->text << "\n";
        }
        return;

    case NodeKind::ExprStmt:
        genExprToA(stmt->children[0]);
        return;

    case NodeKind::If:
    {
        std::string elseLabel = newLabel("if_else");
        std::string endLabel = newLabel("if_end");
        genCondition(stmt->children[0], elseLabel);
        genStatement(stmt->children[1]);
        if (stmt->children.size() > 2)
        {
            *codeOut << "    JMP " << endLabel << "\n";
            *codeOut << elseLabel << ":\n";
            genStatement(stmt->children[2]);
            *codeOut << endLabel << ":\n";
        }
        else
        {
            *codeOut << elseLabel << ":\n";
        }
        return;
    }

    case NodeKind::While:
    {
        std::string startLabel = newLabel("while_start");
        std::string endLabel = newLabel("while_end");
        *codeOut << startLabel << ":\n";
        genCondition(stmt->children[0], endLabel);
        genStatement(stmt->children[1]);
        *codeOut << "    JMP " << startLabel << "\n";
        *codeOut << endLabel << ":\n";
        return;
    }

    case NodeKind::For:
    {
        std::string startLabel = newLabel("for_start");
        std::string endLabel = newLabel("for_end");
        genExprToA(stmt->children[0]);   // init
        *codeOut << startLabel << ":\n";
        genCondition(stmt->children[1], endLabel);
        genStatement(stmt->children[3]);
        genExprToA(stmt->children[2]);   // post
        *codeOut << "    JMP " << startLabel << "\n";
        *codeOut << endLabel << ":\n";
        return;
    }

    case NodeKind::Return:
        if (!stmt->children.empty())
        {
            genExprToA(stmt->children[0]);
        }
        *codeOut << "    RET\n";
        return;

    default:
        throw std::runtime_error(
            "Мини-C: строка " + std::to_string(stmt->line) + ": недопустимый оператор");
    }
}

void Compiler::genBlock(const NodePtr& block)
{
    for (const auto& stmt : block->children)
    {
        genStatement(stmt);
    }
}

void Compiler::genFunction(const NodePtr& fn)
{
    currentFunction = fn->text;
    *codeOut << fn->text << ":\n";
    genBlock(fn->children.back());
    *codeOut << "    LDI A, 0\n";
    *codeOut << "    RET\n";
    currentFunction.clear();
}

std::string Compiler::compile(const std::string& source)
{
    pos = 0;
    labelCounter = 0;
    currentFunction.clear();
    constants.clear();
    functions.clear();
    arraySizes.clear();
    arrayBaseAddr.clear();
    globalVars.clear();
    usesScreenHelper = false;

    lex(source);
    NodePtr program = parseProgram();
    collectDeclarations(program);

    std::ostringstream code;
    std::ostringstream data;
    codeOut = &code;
    dataOut = &data;

    bool hasMain = functions.find("main") != functions.end();
    if (!hasMain)
    {
        throw std::runtime_error("Мини-C: не найдена функция int main()");
    }

    code << "    JMP main\n";

    bool usesArrays = !arraySizes.empty();

    for (const auto& decl : program->children)
    {
        if (decl->kind == NodeKind::FuncDecl)
        {
            genFunction(decl);
        }
    }

    if (usesArrays || usesScreenHelper)
    {
        // A = offset (0-255). HL += offset за ОДИН шаг через ADDHL
        // (раньше был цикл INCHL - O(offset); индекс массива всегда
        // < 256, поэтому старший байт смещения всегда 0).
        code << "__mc_hladd:\n";
        code << "    PUSH A\n";
        code << "    POP C\n";
        code << "    LDI B, 0\n";
        code << "    ADDHL B, C\n";
        code << "    RET\n";
    }

    if (usesScreenHelper)
    {
        // Вход: A = y (0-24), __mc_scr_x уже = x (0-79, см.
        // genScreenAddress). Копит y*80+x как настоящую 16-битную пару
        // байт через ADD/ADC (перенос между байтами - тот же приём,
        // что и в ASSEMBLY.md для сложения многобайтовых чисел; 8-битный
        // MUL тут не годится - 24*80=1920 не влезает в байт), затем
        // ОДИН ADDHL - вместо тысяч INCHL, что было раньше.
        code << "__mc_screen_offset:\n";
        code << "    STA __mc_so_y\n";
        code << "    LDI A, 0\n";
        code << "    STA __mc_so_accLow\n";
        code << "    STA __mc_so_accHigh\n";
        code << "__mc_screen_offset_loop:\n";
        code << "    LDA __mc_so_y\n";
        code << "    LDI B, 0\n";
        code << "    CMP B\n";
        code << "    JZ __mc_screen_offset_y_done\n";
        code << "    LDA __mc_so_accLow\n";
        code << "    LDI B, 80\n";
        code << "    ADD B\n";
        code << "    STA __mc_so_accLow\n";
        code << "    LDA __mc_so_accHigh\n";
        code << "    LDI B, 0\n";
        code << "    ADC B\n";
        code << "    STA __mc_so_accHigh\n";
        code << "    LDA __mc_so_y\n";
        code << "    LDI B, 1\n";
        code << "    SUB B\n";
        code << "    STA __mc_so_y\n";
        code << "    JMP __mc_screen_offset_loop\n";
        code << "__mc_screen_offset_y_done:\n";
        code << "    LDA __mc_scr_x\n";
        code << "    PUSH A\n";
        code << "    POP B\n";
        code << "    LDA __mc_so_accLow\n";
        code << "    ADD B\n";
        code << "    STA __mc_so_accLow\n";
        code << "    LDA __mc_so_accHigh\n";
        code << "    LDI B, 0\n";
        code << "    ADC B\n";
        code << "    STA __mc_so_accHigh\n";
        code << "    LDA __mc_so_accHigh\n";
        code << "    PUSH A\n";
        code << "    POP B\n";
        code << "    LDA __mc_so_accLow\n";
        code << "    PUSH A\n";
        code << "    POP C\n";
        code << "    ADDHL B, C\n";
        code << "    RET\n";

        data << "__mc_scr_x: DB 0\n";
        data << "__mc_scr_y: DB 0\n";
        data << "__mc_so_y: DB 0\n";
        data << "__mc_so_accLow: DB 0\n";
        data << "__mc_so_accHigh: DB 0\n";
        data << "__mc_pc_ch: DB 0\n";
        data << "__mc_sc_fg: DB 0\n";
        data << "__mc_sc_bg: DB 0\n";
        data << "__mc_ps_x: DB 0\n";
        data << "__mc_ps_y: DB 0\n";
        data << "__mc_ps_i: DB 0\n";
        data << "__mc_ps_ch: DB 0\n";
    }

    for (const auto& name : globalVars)
    {
        data << name << ": DB 0\n";
    }

    for (const auto& decl : program->children)
    {
        if (decl->kind == NodeKind::ArrayDecl)
        {
            if (arrayBaseAddr.count(decl->text)) continue;   // маппированный - alias на внешнюю память, своей DB не нужно

            int size = arraySizes[decl->text];
            data << decl->text << ": DB 0\n";
            for (int i = 1; i < size; i++)
            {
                data << "    DB 0\n";
            }
        }
        else if (decl->kind == NodeKind::FuncDecl)
        {
            for (const auto& paramName : functions[decl->text].paramGlobals)
            {
                data << mangleParam(decl->text, paramName) << ": DB 0\n";
            }
        }
    }

    codeOut = nullptr;
    dataOut = nullptr;

    return code.str() + data.str();
}
