#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

// Компилятор мини-C - переводит текст на урезанном Си-подобном языке
// в ТЕКСТ на уже существующем ассемблере этого проекта (тот же
// синтаксис, что понимает Assembler::assemble) - дальше он идёт по
// уже готовому пути (Disk::build -> Assembler -> .RUN). См.
// ASSEMBLY.md, раздел "Мини-C" - там же полное описание языка и его
// осознанных ограничений (только 8-битный int, только глобальные
// переменные, функции без рекурсии, poke/peek только по константным
// адресам - всё это следствие реальных возможностей этого CPU, не
// произвольные упрощения).
//
// Бросает std::runtime_error с текстом ошибки (строка исходника +
// причина), если исходник некорректен - Disk::build() ловит это так
// же, как уже ловит ошибки Assembler::assemble (STATUS=2).
class Compiler
{
public:

    std::string compile(const std::string& source);

private:

    // ---- Лексер ----

    enum class TokType
    {
        END, IDENT, NUMBER, KEYWORD, PUNCT, STRING
    };

    struct Token
    {
        TokType type;
        std::string text;
        long long value;
        int line;
    };

    std::vector<Token> tokens;
    size_t pos;

    void lex(const std::string& source);

    const Token& peek() const;
    const Token& advance();
    bool check(const std::string& text) const;
    bool match(const std::string& text);
    const Token& expect(const std::string& text);
    const Token& expectIdent();
    [[noreturn]] void error(const std::string& message) const;

    // ---- AST ----

    enum class NodeKind
    {
        Program, VarDecl, ArrayDecl, ConstDecl, FuncDecl, Param,
        Block, If, While, For, Return, ExprStmt,
        Assign, IndexAssign, LogicalOr, LogicalAnd, BinOp, UnaryOp,
        Call, Index, Ident, Number, Poke, Peek,
        PrintChar, PrintStr, SetColor, ClearScreen, ExecChild,
        ModLoad, SoundPlay, SoundStop, SoundPause, SoundResume, SoundSetVolume
    };

    struct Node
    {
        NodeKind kind;
        std::string text;              // имя/оператор
        long long value = 0;           // для Number
        std::vector<std::shared_ptr<Node>> children;
        int line = 0;
    };

    using NodePtr = std::shared_ptr<Node>;

    NodePtr node(NodeKind kind);

    NodePtr parseProgram();
    NodePtr parseTopLevelDecl();
    NodePtr parseFuncDecl(const std::string& name);
    NodePtr parseBlock();
    NodePtr parseStatement();
    NodePtr parseVarDeclStatement();
    NodePtr parseExprStatement();

    NodePtr parseExpr();
    NodePtr parseAssignment();
    NodePtr parseLogicalOr();
    NodePtr parseLogicalAnd();
    NodePtr parseEquality();
    NodePtr parseRelational();
    NodePtr parseBitwiseOr();
    NodePtr parseBitwiseXor();
    NodePtr parseBitwiseAnd();
    NodePtr parseShift();
    NodePtr parseAdditive();
    NodePtr parseMultiplicative();
    NodePtr parseUnary();
    NodePtr parsePrimary();

    // ---- Семантика (сбор объявлений перед кодогеном - чтобы функции/
    // константы можно было использовать до текстового места их
    // объявления, как и метки в самом ассемблере) ----

    struct FunctionInfo
    {
        std::vector<std::string> paramGlobals;   // мангленные имена параметров
    };

    std::map<std::string, long long> constants;
    std::map<std::string, FunctionInfo> functions;
    std::map<std::string, int> arraySizes;
    std::map<std::string, long long> arrayBaseAddr;   // маппированные массивы (`int arr[N] = адрес;`) - alias на внешнюю память (MMIO), без собственной DB-ячейки
    std::vector<std::string> globalVars;   // все `int x;` - и верхнего уровня, и внутри функций (переменных без глобальной DB-ячейки в этом языке не бывает)

    void collectDeclarations(const NodePtr& program);
    void collectVarDecls(const NodePtr& n);
    long long foldConst(const NodePtr& expr) const;   // для poke/peek адресов и const ИМЯ = выражение

    // ---- Кодоген ----

    std::ostringstream* codeOut = nullptr;
    std::ostringstream* dataOut = nullptr;
    int labelCounter = 0;
    std::string currentFunction;

    std::string newLabel(const std::string& hint);
    std::string mangleParam(const std::string& func, const std::string& param) const;

    void genFunction(const NodePtr& fn);
    void genBlock(const NodePtr& block);
    void genStatement(const NodePtr& stmt);
    void genExprToA(const NodePtr& expr);
    void genCondition(const NodePtr& expr, const std::string& falseLabel);
    void genComparisonToA(const NodePtr& expr);
    void genAddressOf(const NodePtr& indexNode);   // вычисляет HL = массив+индекс

    // ---- Экранные встроенные функции (print_char/print_str/set_color/
    // clear_screen - см. ASSEMBLY.md, "Мини-C") ----

    bool usesScreenHelper = false;    // нужен ли __mc_screen_offset (эмитится один раз, если хоть раз использован)

    void genPrintChar(const NodePtr& expr);
    void genPrintStr(const NodePtr& expr);
    void genModLoad(const NodePtr& expr);
    void genSetColor(const NodePtr& expr);
    void genScreenAddress(long long base, const NodePtr& xExpr, const NodePtr& yExpr);   // HL = base + y*80 + x
};
