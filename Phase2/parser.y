%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "alpha_lexer.h"
#include "Phase2Functions.h"

#define PRINT_RULE(rule) printf("  Rule: %s\n", rule)

struct alpha_token_t global_token;
extern int alpha_yylex(void *yylval);
extern TokenList syntaxList;

int yylex(void);
void yyerror(const char *msg);

/* Global state */
int currentScope      = 0;
int anonFuncCounter   = 0;
int functionDepth     = 0;   /* nesting depth of function definitions   */
int loopDepth         = 0;   /* nesting depth of while / for loops      */
int scopeSpaceCounter = 1;

extern int syntax_errors;
extern int yylineno;

/* Helper: centralised access check
 *  Returns 1 if accessing `sym` from `curScope` crosses a
 *  function boundary (illegal for locals / formals).              */
static int accessViolation(Symbol_t *sym) {
    if (!sym) return 0;
    if (sym->type != LOCAL_VAR && sym->type != FORMAL_ARG) return 0;
    if (sym->scope == 0) return 0;

    int symDepth = (sym->type == FORMAL_ARG) ? sym->funcDepth - 1 : sym->funcDepth;
    return symDepth < functionDepth;
}
%}

/* YYSTYPE */
%union {
    struct alpha_token_t *token;
    struct Symbol_t      *sym;
}

/* Non-terminal semantic types */
%type <token> lvalue expr assignexpr term primary member
%type <token> call const objectdef funcdef
%type <sym>   funcprefix

/* Terminal tokens */
%token <token> IF ELSE WHILE FOR FUNCTION RETURN BREAK CONTINUE
%token <token> AND NOT OR TRUE FALSE NIL LOCAL
%token <token> ASSIGN PLUS MINUS MULTIPLY DIVIDE MODULUS
%token <token> EQUAL NOT_EQUAL INCREMENT DECREMENT
%token <token> GREATER_THAN LESS_THAN GREATER_EQUAL LESS_EQUAL
%token <token> LEFT_PARENTHESIS RIGHT_PARENTHESIS
%token <token> LEFT_BRACE RIGHT_BRACE
%token <token> LEFT_SQUARE_BRACKET RIGHT_SQUARE_BRACKET
%token <token> SEMICOLON COMMA COLON DOUBLE_COLON DOT DOUBLE_DOT
%token <token> INTCON REALCON STR ID
%token <token> COMMEN UMINUS

/* Precedence  (low → high) */
%right    ASSIGN
%left     OR
%left     AND
%nonassoc EQUAL NOT_EQUAL
%nonassoc GREATER_THAN GREATER_EQUAL LESS_THAN LESS_EQUAL
%left     PLUS MINUS
%left     MULTIPLY DIVIDE MODULUS
%right    NOT INCREMENT DECREMENT UMINUS
%left     DOT DOUBLE_DOT
%left     LEFT_PARENTHESIS RIGHT_PARENTHESIS
%left     LEFT_SQUARE_BRACKET RIGHT_SQUARE_BRACKET

/* Dangling-else: exactly 1 shift/reduce conflict expected */
%expect 1

%start program

%%

program:
      /* empty */              { PRINT_RULE("program -> epsilon"); }
    | program stmt             { PRINT_RULE("program -> program stmt"); }
;

stmt:
      expr SEMICOLON           { PRINT_RULE("stmt -> expr ;"); }
    | ifstmt                   { PRINT_RULE("stmt -> ifstmt"); }
    | whilestmt                { PRINT_RULE("stmt -> whilestmt"); }
    | forstmt                  { PRINT_RULE("stmt -> forstmt"); }
    | returnstmt               { PRINT_RULE("stmt -> returnstmt"); }
    | BREAK SEMICOLON {
          PRINT_RULE("stmt -> break ;");
          if (loopDepth == 0) {
              printf("[SYNTAX ERROR] 'break' outside loop at line %d\n",
                     $1->lineNumber);
              syntax_errors++;
          }
      }
    | CONTINUE SEMICOLON {
          PRINT_RULE("stmt -> continue ;");
          if (loopDepth == 0) {
              printf("[SYNTAX ERROR] 'continue' outside loop at line %d\n",
                     $1->lineNumber);
              syntax_errors++;
          }
      }
    | block                    { PRINT_RULE("stmt -> block"); }
    | funcdef                  { PRINT_RULE("stmt -> funcdef"); }
    | SEMICOLON                { PRINT_RULE("stmt -> ;"); }
    | COMMEN                   { /* absorb comment tokens */ }
;

expr:
      assignexpr               { $$ = $1; }
    | expr PLUS expr           { PRINT_RULE("expr -> expr + expr");  $$ = $1; }
    | expr MINUS expr          { PRINT_RULE("expr -> expr - expr");  $$ = $1; }
    | expr MULTIPLY expr       { PRINT_RULE("expr -> expr * expr");  $$ = $1; }
    | expr DIVIDE expr         { PRINT_RULE("expr -> expr / expr");  $$ = $1; }
    | expr MODULUS expr        { PRINT_RULE("expr -> expr %% expr"); $$ = $1; }
    | expr GREATER_THAN expr   { PRINT_RULE("expr -> expr > expr");  $$ = $1; }
    | expr GREATER_EQUAL expr  { PRINT_RULE("expr -> expr >= expr"); $$ = $1; }
    | expr LESS_THAN expr      { PRINT_RULE("expr -> expr < expr");  $$ = $1; }
    | expr LESS_EQUAL expr     { PRINT_RULE("expr -> expr <= expr"); $$ = $1; }
    | expr EQUAL expr          { PRINT_RULE("expr -> expr == expr"); $$ = $1; }
    | expr NOT_EQUAL expr      { PRINT_RULE("expr -> expr != expr"); $$ = $1; }
    | expr AND expr            { PRINT_RULE("expr -> expr and expr"); $$ = $1; }
    | expr OR expr             { PRINT_RULE("expr -> expr or expr");  $$ = $1; }
    | term                     { $$ = $1; }
;

term:
      LEFT_PARENTHESIS expr RIGHT_PARENTHESIS {
          PRINT_RULE("term -> (expr)");
          $$ = $2;
      }
    | MINUS expr %prec UMINUS {
          PRINT_RULE("term -> -expr");
          $$ = $2;
      }
    | NOT expr {
          PRINT_RULE("term -> not expr");
          $$ = $2;
      }
    | INCREMENT lvalue {
          PRINT_RULE("term -> ++lvalue");
          Symbol_t *sym = resolveSymbol($2->tokenContent, currentScope, 0);
          if (sym && (sym->type == USER_FUNC || sym->type == LIB_FUNC)) {
              printf("[SYNTAX ERROR] Cannot increment function '%s' at line %d\n",
                     $2->tokenContent, $2->lineNumber);
              syntax_errors++;
          }
          $$ = $2;
      }
    | lvalue INCREMENT {
          PRINT_RULE("term -> lvalue++");
          Symbol_t *sym = resolveSymbol($1->tokenContent, currentScope, 0);
          if (sym && (sym->type == USER_FUNC || sym->type == LIB_FUNC)) {
              printf("[SYNTAX ERROR] Cannot increment function '%s' at line %d\n",
                     $1->tokenContent, $1->lineNumber);
              syntax_errors++;
          }
          $$ = $1;
      }
    | DECREMENT lvalue {
          PRINT_RULE("term -> --lvalue");
          Symbol_t *sym = resolveSymbol($2->tokenContent, currentScope, 0);
          if (sym && (sym->type == USER_FUNC || sym->type == LIB_FUNC)) {
              printf("[SYNTAX ERROR] Cannot decrement function '%s' at line %d\n",
                     $2->tokenContent, $2->lineNumber);
              syntax_errors++;
          }
          $$ = $2;
      }
    | lvalue DECREMENT {
          PRINT_RULE("term -> lvalue--");
          Symbol_t *sym = resolveSymbol($1->tokenContent, currentScope, 0);
          if (sym && (sym->type == USER_FUNC || sym->type == LIB_FUNC)) {
              printf("[SYNTAX ERROR] Cannot decrement function '%s' at line %d\n",
                     $1->tokenContent, $1->lineNumber);
              syntax_errors++;
          }
          $$ = $1;
      }
    | primary                  { $$ = $1; }
;

assignexpr:
    lvalue ASSIGN expr {
        PRINT_RULE("assignexpr -> lvalue = expr");
        if ($1->tokenCategory == IDENT) {
            Symbol_t *sym = resolveSymbol($1->tokenContent, currentScope, 0);
            if (sym) {
                if (sym->type == USER_FUNC) {
                    printf("[SYNTAX ERROR] Cannot assign to user function '%s' at line %d\n",
                           $1->tokenContent, $1->lineNumber);
                    syntax_errors++;
                } else if (sym->type == LIB_FUNC) {
                    printf("[SYNTAX ERROR] Cannot assign to library function '%s' at line %d\n",
                           $1->tokenContent, $1->lineNumber);
                    syntax_errors++;
                }
            }
        }
        $$ = $1;
    }
    | call ASSIGN expr {
        PRINT_RULE("assignexpr -> lvalue = expr");
        printf("[SYNTAX ERROR] Cannot assign to function call result at line %d\n",
               $2->lineNumber);
        syntax_errors++;
        $$ = $1;
    }
;

primary:
      lvalue {
          PRINT_RULE("primary -> lvalue");
          $$ = $1;
      }
    | call {
          PRINT_RULE("primary -> call");
          $$ = $1;
      }
    | objectdef {
          PRINT_RULE("primary -> objectdef");
          $$ = $1;
      }
    | LEFT_PARENTHESIS funcdef RIGHT_PARENTHESIS {
          PRINT_RULE("primary -> (funcdef)");
          $$ = $2;
      }
    | const {
          PRINT_RULE("primary -> const");
          $$ = $1;
      }
;

lvalue:
    ID {
        PRINT_RULE("lvalue -> id");
        Symbol_t *sym = resolveSymbol($1->tokenContent, currentScope, 0);

        if (!sym) {
            /* Auto-declare new variable */
            SymbolType type = (currentScope == 0) ? GLOBAL_VAR : LOCAL_VAR;
            insertSymbol($1->tokenContent, type, currentScope, $1->lineNumber);
        } else {
            /* Centralised access-violation check */
            if (accessViolation(sym)) {
                printf("[SYNTAX ERROR] Cannot access '%s' inside nested function at line %d\n",
                       $1->tokenContent, $1->lineNumber);
                syntax_errors++;
            }
        }
        $$ = $1;
    }
  | LOCAL ID {
        PRINT_RULE("lvalue -> local id");
        Symbol_t *sym = lookupSymbolInScope($2->tokenContent, currentScope);

        if (sym) {
            /* Already exists in this scope — reference it (local id is
               essentially a no-op if the name is already local/formal). */
        } else {
            if (isLibraryFunction($2->tokenContent)) {
                printf("[SYNTAX ERROR] Cannot shadow library function '%s' with local (line %d)\n",
                       $2->tokenContent, $2->lineNumber);
                syntax_errors++;
            } else {
                SymbolType type = (currentScope == 0) ? GLOBAL_VAR : LOCAL_VAR;
                insertSymbol($2->tokenContent, type, currentScope, $2->lineNumber);
            }
        }
        $$ = $2;
    }
  | DOUBLE_COLON ID {
        PRINT_RULE("lvalue -> ::id");
        Symbol_t *sym = lookupSymbolInScope($2->tokenContent, 0);
        if (!sym) {
            printf("[SYNTAX ERROR] Undefined global '::%s' at line %d\n",
                   $2->tokenContent, $2->lineNumber);
            syntax_errors++;
        }
        $$ = $2;
    }
  | member { $$ = $1; }
;


member:
      lvalue DOT ID                                         { PRINT_RULE("member -> lvalue.id"); $$ = $1; }
    | lvalue LEFT_SQUARE_BRACKET expr RIGHT_SQUARE_BRACKET  { PRINT_RULE("member -> lvalue[expr]"); $$ = $1; }
    | call DOT ID                                           { PRINT_RULE("member -> call.id"); $$ = $3; }
    | call LEFT_SQUARE_BRACKET expr RIGHT_SQUARE_BRACKET    { PRINT_RULE("member -> call[expr]"); $$ = $1; }
;

call:
      call LEFT_PARENTHESIS elist RIGHT_PARENTHESIS {
          PRINT_RULE("call -> call(elist)");
          $$ = $1;
      }
    | lvalue callsuffix {
          PRINT_RULE("call -> lvalue callsuffix");
          $$ = $1;
      }
    | LEFT_PARENTHESIS funcdef RIGHT_PARENTHESIS
      LEFT_PARENTHESIS elist RIGHT_PARENTHESIS {
          PRINT_RULE("call -> (funcdef)(elist)");
          $$ = $2;
      }
;

callsuffix:
      normcall     { PRINT_RULE("callsuffix -> normcall"); }
    | methodcall   { PRINT_RULE("callsuffix -> methodcall"); }
;

normcall:
    LEFT_PARENTHESIS elist RIGHT_PARENTHESIS {
        PRINT_RULE("normcall -> (elist)");
    }
;

methodcall:
    DOUBLE_DOT ID LEFT_PARENTHESIS elist RIGHT_PARENTHESIS {
        PRINT_RULE("methodcall -> ..id(elist)");
    }
;

elist:
      /* empty */
    | expr
    | elist COMMA expr
;

/* =============================================================================================*/
objectdef:
      LEFT_SQUARE_BRACKET elist RIGHT_SQUARE_BRACKET   { PRINT_RULE("objectdef -> [elist]"); }
    | LEFT_SQUARE_BRACKET indexed RIGHT_SQUARE_BRACKET { PRINT_RULE("objectdef -> [indexed]"); }
;

indexed:
      indexedelem
    | indexed COMMA indexedelem
;

indexedelem:
    LEFT_BRACE expr COLON expr RIGHT_BRACE {
        PRINT_RULE("indexedelem -> {expr:expr}");
    }
;


block:
    LEFT_BRACE {
        currentScope++;
    }
    stmts
    RIGHT_BRACE {
        hideScope(currentScope);
        currentScope--;
    }
;

/* Function body — identical syntax to block but does NOT
   touch currentScope (funcdef already incremented it).  */
funcbody:
    LEFT_BRACE stmts RIGHT_BRACE
;

stmts:
      /* empty */
    | stmts stmt
;

/* funcdef */
funcdef:
      /* Named function:  function id (idlist) { ... }  */
      FUNCTION funcprefix
      LEFT_PARENTHESIS { currentScope++; }
      idlist {
          if ($2) attachFormalsToFunction($2, currentScope);
      }
      RIGHT_PARENTHESIS
      funcbody {
          PRINT_RULE("funcdef -> function id(idlist) block");
          hideScope(currentScope);
          currentScope--;
          functionDepth--;
      }

      /* Anonymous function:  function (idlist) { ... }  */
    | FUNCTION LEFT_PARENTHESIS {
          char temp[32];
          sprintf(temp, "$%d", anonFuncCounter++);
          insertSymbol(temp, USER_FUNC, currentScope, yylineno);
          functionDepth++;
          currentScope++;
      }
      idlist {
          char temp[32];
          sprintf(temp, "$%d", anonFuncCounter - 1);
          Symbol_t *anonSym = lookupSymbolInScope(temp, currentScope - 1);
          if (anonSym) attachFormalsToFunction(anonSym, currentScope);
      }
      RIGHT_PARENTHESIS
      funcbody {
          PRINT_RULE("funcdef -> function(idlist) block");
          hideScope(currentScope);
          currentScope--;
          functionDepth--;
      }
;

funcprefix:
    ID {
        if (isLibraryFunction($1->tokenContent)) {
            printf("[SYNTAX ERROR] Cannot redefine library function '%s' (line %d)\n",
                   $1->tokenContent, $1->lineNumber);
            syntax_errors++;
            $$ = NULL;
        } else if (lookupSymbolInScope($1->tokenContent, currentScope)) {
            printf("[SYNTAX ERROR] Symbol '%s' already declared in scope %d (line %d)\n",
                   $1->tokenContent, currentScope, $1->lineNumber);
            syntax_errors++;
            $$ = NULL;
        } else {
            insertSymbol($1->tokenContent, USER_FUNC, currentScope, $1->lineNumber);
            $$ = lookupSymbolInScope($1->tokenContent, currentScope);
        }
        functionDepth++;
    }
;

idlist:
      /* empty */
    | idseq
;

idseq:
      ID {
          Symbol_t *sym = lookupSymbolInScope($1->tokenContent, currentScope);
          if (sym) {
              printf("[SYNTAX ERROR] Duplicate formal '%s' (line %d)\n",
                     $1->tokenContent, $1->lineNumber);
              syntax_errors++;
          } else if (isLibraryFunction($1->tokenContent)) {
              printf("[SYNTAX ERROR] Cannot use library function '%s' as formal (line %d)\n",
                     $1->tokenContent, $1->lineNumber);
              syntax_errors++;
          } else {
              insertSymbol($1->tokenContent, FORMAL_ARG, currentScope, $1->lineNumber);
          }
      }
    | idseq COMMA ID {
          Symbol_t *sym = lookupSymbolInScope($3->tokenContent, currentScope);
          if (sym) {
              printf("[SYNTAX ERROR] Duplicate formal '%s' (line %d)\n",
                     $3->tokenContent, $3->lineNumber);
              syntax_errors++;
          } else if (isLibraryFunction($3->tokenContent)) {
              printf("[SYNTAX ERROR] Cannot use library function '%s' as formal (line %d)\n",
                     $3->tokenContent, $3->lineNumber);
              syntax_errors++;
          } else {
              insertSymbol($3->tokenContent, FORMAL_ARG, currentScope, $3->lineNumber);
          }
      }
;

/* const */
const:
      INTCON   { $$ = $1; }
    | REALCON  { $$ = $1; }
    | STR      { $$ = $1; }
    | NIL      { $$ = $1; }
    | TRUE     { $$ = $1; }
    | FALSE    { $$ = $1; }
;

ifstmt:
      IF LEFT_PARENTHESIS expr RIGHT_PARENTHESIS stmt ELSE stmt {
          PRINT_RULE("ifstmt -> if(expr) stmt else stmt");
      }
    | IF LEFT_PARENTHESIS expr RIGHT_PARENTHESIS stmt {
          PRINT_RULE("ifstmt -> if(expr) stmt");
      }
;

whilestmt:
    WHILE LEFT_PARENTHESIS expr RIGHT_PARENTHESIS
    { loopDepth++; }
    stmt
    { loopDepth--; PRINT_RULE("whilestmt -> while(expr) stmt"); }
;

forstmt:
    FOR LEFT_PARENTHESIS elist SEMICOLON expr SEMICOLON elist RIGHT_PARENTHESIS
    { loopDepth++; }
    stmt
    { loopDepth--; PRINT_RULE("forstmt -> for(elist;expr;elist) stmt"); }
;

returnstmt:
      RETURN SEMICOLON {
          PRINT_RULE("returnstmt -> return ;");
          if (functionDepth == 0) {
              printf("[SYNTAX ERROR] 'return' outside function at line %d\n",
                     $1->lineNumber);
              syntax_errors++;
          }
      }
    | RETURN expr SEMICOLON {
          PRINT_RULE("returnstmt -> return expr ;");
          if (functionDepth == 0) {
              printf("[SYNTAX ERROR] 'return' outside function at line %d\n",
                     $1->lineNumber);
              syntax_errors++;
          }
      }
;

%%

int yylex(void) {
    Token *tok_ptr = NULL;
    int token_type = alpha_yylex(&tok_ptr);

    if (token_type < 0 || !tok_ptr) return 0;
    global_token = *tok_ptr;

    struct alpha_token_t *tok = malloc(sizeof(struct alpha_token_t));
    if (!tok) { fprintf(stderr, "[FATAL] malloc\n"); exit(1); }
    *tok = *tok_ptr;
    tok->tokenContent = tok_ptr->tokenContent
                        ? strdup(tok_ptr->tokenContent)
                        : strdup("");

    listAppend(&syntaxList, tok);
    yylval.token = tok;

    switch (tok_ptr->tokenCharacteristic) {
        case IF_:       return IF;
        case ELSE_:     return ELSE;
        case WHILE_:    return WHILE;
        case FOR_:      return FOR;
        case FUNCTION_: return FUNCTION;
        case RETURN_:   return RETURN;
        case BREAK_:    return BREAK;
        case CONTINUE_: return CONTINUE;
        case AND_:      return AND;
        case NOT_:      return NOT;
        case OR_:       return OR;
        case LOCAL_:    return LOCAL;
        case TRUE_:     return TRUE;
        case FALSE_:    return FALSE;
        case NIL_:      return NIL;
        case ASSIGN_:        return ASSIGN;
        case PLUS_:          return PLUS;
        case MINUS_:         return MINUS;
        case MULTIPLY_:      return MULTIPLY;
        case DIVIDE_:        return DIVIDE;
        case MODULUS_:       return MODULUS;
        case EQUAL_:         return EQUAL;
        case NOT_EQUAL_:     return NOT_EQUAL;
        case INCREMENT_:     return INCREMENT;
        case DECREMENT_:     return DECREMENT;
        case GREATER_THAN_:  return GREATER_THAN;
        case LESS_THAN_:     return LESS_THAN;
        case GREATER_EQUAL_: return GREATER_EQUAL;
        case LESS_EQUAL_:    return LESS_EQUAL;
        case LEFT_BRACE_:            return LEFT_BRACE;
        case RIGHT_BRACE_:           return RIGHT_BRACE;
        case LEFT_SQUARE_BRACKET_:   return LEFT_SQUARE_BRACKET;
        case RIGHT_SQUARE_BRACKET_:  return RIGHT_SQUARE_BRACKET;
        case LEFT_PARENTHESIS_:      return LEFT_PARENTHESIS;
        case RIGHT_PARENTHESIS_:     return RIGHT_PARENTHESIS;
        case SEMICOLON_:    return SEMICOLON;
        case COMMA_:        return COMMA;
        case COLON_:        return COLON;
        case DOUBLE_COLON_: return DOUBLE_COLON;
        case DOT_:          return DOT;
        case DOUBLE_DOT_:   return DOUBLE_DOT;
        case LINE_COMMENTS_:
        case BLOCK_COMMENTS_:
        case NESTED_COMMENTS_: return COMMEN;
        case NOCHARACTERISTIC_:
            switch (tok_ptr->tokenCategory) {
                case INTCONST:  return INTCON;
                case REALCONST: return REALCON;
                case IDENT:     return ID;
                case STRING:    return STR;
                default:        return 0;
            }
        default: return 0;
    }
}

void yyerror(const char *msg) {
    fprintf(stderr, "[SYNTAX ERROR] %s at line %d\n", msg, yylineno);
}