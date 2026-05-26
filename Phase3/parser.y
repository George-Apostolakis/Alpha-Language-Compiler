%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "alpha_lexer.h"
#include "Phase2Functions.h"
#include "IntermediateCode.h"

#define PRINT_RULE(rule) printf("  Rule: %s\n", rule)

/* ── Globals (Phase 2) ─────────────────────────────────── */
struct alpha_token_t global_token;
extern int   alpha_yylex(void *yylval);
extern TokenList syntaxList;

int yylex(void);
void yyerror(const char *msg);

int currentScope      = 0;
int anonFuncCounter   = 0;
int functionDepth     = 0;
int loopDepth         = 0;   /* kept for Phase-2 compat (accessViolation) */
int scopeSpaceCounter = 1;

extern int syntax_errors;
extern int yylineno;
extern int currQuad;

/* ── Phase-3 globals ───────────────────────────────────── */
/* Stack to save/restore the enclosing function's sym while parsing nested funcdefs */
#define MAX_FUNCDEPTH 64
Symbol_t* funcSymStack[MAX_FUNCDEPTH];
int       funcSymTop  = -1;
Symbol_t* funcSym     = NULL;          /* current function being parsed */

/* Jump-patch stack: each funcdef pushes the quad-index of its entry jump */
unsigned int jumpStack[MAX_FUNCDEPTH];
int          jumpStackTop = -1;

/* Return-list stack (one IntList per nested function) */
IntList retListStack[MAX_FUNCDEPTH];
int     retListTop = -1;
IntList retList;

/* lcs (loop-counter stack) saved when entering a function */
extern Lc_stack_t *lcs_top;
Lc_stack_t *saved_lcs_top = NULL;

/* Offsets */
extern int formalArgOffset;
extern int functionLocalOffset;
extern int programVarOffset;

/* Pending funcdef entry jumps — per-depth stack */
#define MAX_PENDING_JUMPS 256
#define MAX_DEPTH 64
static int pendingFuncJumps[MAX_DEPTH][MAX_PENDING_JUMPS];
static int pendingFuncJumpsTops[MAX_DEPTH];
static int pendingDepthInit = 0;

static void ensurePendingInit(void) {
    if (!pendingDepthInit) {
        for (int i = 0; i < MAX_DEPTH; i++) pendingFuncJumpsTops[i] = -1;
        pendingDepthInit = 1;
    }
}

void patchPendingFuncJumps(void) {
    ensurePendingInit();
    int d = functionDepth;
    if (pendingFuncJumpsTops[d] < 0) return;
    int target = nextquad();
    while (pendingFuncJumpsTops[d] >= 0)
        patchlabel(pendingFuncJumps[d][pendingFuncJumpsTops[d]--], target);
}
int insideExprList = 0;

/* ── accessViolation (Phase 2) ─────────────────────────── */
static int accessViolation(Symbol_t *sym) {
    if (!sym) return 0;
    if (sym->type != LOCAL_VAR && sym->type != FORMAL_ARG) return 0;
    if (sym->scope == 0) return 0;
    /* FORMAL_ARG: inserted with funcDepth = functionDepth+1 at parse time.
       Violation only if sym->funcDepth < functionDepth (belongs to outer function).
       If sym->funcDepth == functionDepth, it belongs to the current function → OK. */
    if (sym->type == FORMAL_ARG)
        return sym->funcDepth < functionDepth;
    else
        return sym->funcDepth < functionDepth;
}
%}

/* ── %code requires ─────────────────────────────────────── */
%code requires {
    #include "IntermediateCode.h"
}

%code provides {
    void patchPendingFuncJumps(void);
}

/* ── YYSTYPE ─────────────────────────────────────────────── */
%union {
    struct alpha_token_t *token;
    struct Symbol_t      *sym;       /* funcprefix, funcdef */

    expr_t               *expr;      /* Phase-3 expressions  */
    stmt_t                stmt;      /* break/cont/ret lists */
    forprefix_t           forprefix; /* for-loop helper      */
    int                   intValue;  /* quad indices (M, N, ifprefix …) */
    callstruct_t          callstruct;/* normcall / methodcall */
    indexed_t            *indexed;
}

/* ── Non-terminal types ──────────────────────────────────── */
/* Phase-2 compatible tokens still declared as <token> where
   the rule does not need an expr_t (e.g. pure syntactic rules). */

%type <expr>       expr assignexpr term primary lvalue member call const objectdef
%type <expr>       elist
%type <stmt>       stmt stmts block loopstmt returnstmt
%type <stmt>       ifstmt whilestmt forstmt
%type <sym>        funcdef funcprefix
%type <intValue>   ifprefix elseprefix whilestart whilecond M N
%type <forprefix>  forprefix
%type <callstruct> callsuffix normcall methodcall
%type <indexed>    indexed indexedelem

/* ── Terminal tokens ─────────────────────────────────────── */
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

/* ── Operator precedence (same as Phase 2) ───────────────── */
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

%nonassoc ELSE   /* resolve dangling-else */

%expect 1
%start program

%%

/* ═══════════════════════════════════════════════════════════
   program / stmts / stmt
   ═══════════════════════════════════════════════════════════ */
program:
      /* empty */        { PRINT_RULE("program -> epsilon"); }
    | program M stmt     {
          PRINT_RULE("program -> program stmt");
          /* patch pending funcdef jumps from depth=0 that predate this stmt */
          ensurePendingInit();
          int count = pendingFuncJumpsTops[0] + 1;
          int writeIdx = 0;
          for (int i = 0; i < count; i++) {
              int qno = pendingFuncJumps[0][i];
              if (qno < $2) {
                  patchlabel(qno, $2);
              } else {
                  pendingFuncJumps[0][writeIdx++] = qno;
              }
          }
          pendingFuncJumpsTops[0] = writeIdx - 1;
      }
    | program error      { yyerrok; }
;

/* ── Marker non-terminals (epsilon) ─────────────────────── */
M: /* empty */ { $$ = nextquad(); };
N: /* empty */ { $$ = nextquad(); emit(jump,NULL,NULL,NULL,-1,yylineno); };

/* ── stmts ───────────────────────────────────────────────── */
stmts:
      /* empty */ {
          PRINT_RULE("stmts -> epsilon");
          make_stmt(&$$);
      }
    | stmts M stmt {
          PRINT_RULE("stmts -> stmts stmt");
          make_stmt(&$$);
          /* Patch pending funcdef entry jumps that were added BEFORE
             this stmt (quad index < $2). Those belong to previous funcdefs
             and should jump to $2 (first quad of this non-funcdef stmt).
             Jumps with index >= $2 belong to THIS stmt's funcdef — keep them. */
          ensurePendingInit();
          int d = functionDepth;
          int count = pendingFuncJumpsTops[d] + 1;
          int writeIdx = 0;
          for (int i = 0; i < count; i++) {
              int qno = pendingFuncJumps[d][i];
              if (qno < $2) {
                  patchlabel(qno, $2);
              } else {
                  pendingFuncJumps[d][writeIdx++] = qno;
              }
          }
          pendingFuncJumpsTops[d] = writeIdx - 1;
          $$.breaklist  = mergelist($1.breaklist,  $3.breaklist);
          $$.contlist   = mergelist($1.contlist,   $3.contlist);
          $$.returnlist = mergelist($1.returnlist, $3.returnlist);
      }
;

/* ── stmt ────────────────────────────────────────────────── */
stmt:
      expr SEMICOLON {
          PRINT_RULE("stmt -> expr ;");
          make_stmt(&$$);
          /* materialise a dangling boolean expression */
          if ($1 && $1->type == boolexpr_e &&
              $1->truelist.size > 0 && $1->falselist.size > 0)
              $1 = make_bool_expr($1, 1);
          if (!insideExprList) resettemp();
      }
    | ifstmt   {
          PRINT_RULE("stmt -> ifstmt");
          $$ = $1;
      }
    | whilestmt {
          PRINT_RULE("stmt -> whilestmt");
          $$ = $1;
      }
    | forstmt {
          PRINT_RULE("stmt -> forstmt");
          $$ = $1;
      }
    | returnstmt {
          PRINT_RULE("stmt -> returnstmt");
          $$ = $1;
      }
    | BREAK SEMICOLON {
          PRINT_RULE("stmt -> break ;");
          make_stmt(&$$);
          if (!inLoop()) {
              printf("[SYNTAX ERROR] 'break' outside loop at line %d\n",
                     $1->lineNumber);
              syntax_errors++;
          } else {
              int bq = nextquad();
              emit(jump, NULL, NULL, NULL, -1, yylineno);
              $$.breaklist = newlist(bq);
          }
      }
    | CONTINUE SEMICOLON {
          PRINT_RULE("stmt -> continue ;");
          make_stmt(&$$);
          if (!inLoop()) {
              printf("[SYNTAX ERROR] 'continue' outside loop at line %d\n",
                     $1->lineNumber);
              syntax_errors++;
          } else {
              int cq = nextquad();
              emit(jump, NULL, NULL, NULL, -1, yylineno);
              $$.contlist = newlist(cq);
          }
      }
    | block {
          PRINT_RULE("stmt -> block");
          $$ = $1;
      }
    | funcdef {
          PRINT_RULE("stmt -> funcdef");
          make_stmt(&$$);
      }
    | SEMICOLON {
          PRINT_RULE("stmt -> ;");
          make_stmt(&$$);
      }
    | COMMEN { make_stmt(&$$); }
;

/* ═══════════════════════════════════════════════════════════
   expr
   ═══════════════════════════════════════════════════════════ */
expr:
      assignexpr { $$ = $1; }

    /* ── Arithmetic ── */
    | expr PLUS expr {
          PRINT_RULE("expr -> expr + expr");
          if (!$1 || !$3) { $$ = NULL; yyerrok; }
          else {
              $1 = emit_iftableitem($1, yylineno);
              $3 = emit_iftableitem($3, yylineno);
              check_arith($1, "+"); check_arith($3, "+");
              if ($1->type == constnum_e && $3->type == constnum_e) {
                  $$ = newexpr(arithexpr_e);
                  $$->numConst = $1->numConst + $3->numConst;
                  $$->sym = newtemp();
                  emit(add, $$, newexpr_constnum($1->numConst),
                       newexpr_constnum($3->numConst), -1, yylineno);
              } else {
                  $$ = newexpr(arithexpr_e);
                  $$->sym = istempexpr($1) ? $1->sym
                          : istempexpr($3) ? $3->sym
                          : newtemp();
                  emit(add, $$, $1, $3, -1, yylineno);
              }
          }
      }
    | expr MINUS expr {
          PRINT_RULE("expr -> expr - expr");
          if (!$1 || !$3) { $$ = NULL; yyerrok; }
          else {
              $1 = emit_iftableitem($1, yylineno);
              $3 = emit_iftableitem($3, yylineno);
              check_arith($1, "-"); check_arith($3, "-");
              if ($1->type == constnum_e && $3->type == constnum_e) {
                  $$ = newexpr(arithexpr_e);
                  $$->numConst = $1->numConst - $3->numConst;
                  $$->sym = newtemp();
                  emit(sub, $$, newexpr_constnum($1->numConst),
                       newexpr_constnum($3->numConst), -1, yylineno);
              } else {
                  $$ = newexpr(arithexpr_e);
                  $$->sym = istempexpr($1) ? $1->sym
                          : istempexpr($3) ? $3->sym
                          : newtemp();
                  emit(sub, $$, $1, $3, -1, yylineno);
              }
          }
      }
    | expr MULTIPLY expr {
          PRINT_RULE("expr -> expr * expr");
          if (!$1 || !$3) { $$ = NULL; yyerrok; }
          else {
              $1 = emit_iftableitem($1, yylineno);
              $3 = emit_iftableitem($3, yylineno);
              check_arith($1, "*"); check_arith($3, "*");
              if ($1->type == constnum_e && $3->type == constnum_e) {
                  $$ = newexpr(arithexpr_e);
                  $$->numConst = $1->numConst * $3->numConst;
                  $$->sym = newtemp();
                  emit(mul, $$, newexpr_constnum($1->numConst),
                       newexpr_constnum($3->numConst), -1, yylineno);
              } else {
                  $$ = newexpr(arithexpr_e);
                  $$->sym = istempexpr($1) ? $1->sym
                          : istempexpr($3) ? $3->sym
                          : newtemp();
                  emit(mul, $$, $1, $3, -1, yylineno);
              }
          }
      }
    | expr DIVIDE expr {
          PRINT_RULE("expr -> expr / expr");
          if (!$1 || !$3) { $$ = NULL; yyerrok; }
          else {
              $1 = emit_iftableitem($1, yylineno);
              $3 = emit_iftableitem($3, yylineno);
              check_arith($1, "/"); check_arith($3, "/");
              if ($1->type == constnum_e && $3->type == constnum_e) {
                  $$ = newexpr(arithexpr_e);
                  $$->numConst = ($3->numConst != 0)
                                 ? $1->numConst / $3->numConst : 0;
                  $$->sym = newtemp();
                  emit(divide, $$, newexpr_constnum($1->numConst),
                       newexpr_constnum($3->numConst), -1, yylineno);
              } else {
                  $$ = newexpr(arithexpr_e);
                  $$->sym = istempexpr($1) ? $1->sym
                          : istempexpr($3) ? $3->sym
                          : newtemp();
                  emit(divide, $$, $1, $3, -1, yylineno);
              }
          }
      }
    | expr MODULUS expr {
          PRINT_RULE("expr -> expr %% expr");
          if (!$1 || !$3) { $$ = NULL; yyerrok; }
          else {
              $1 = emit_iftableitem($1, yylineno);
              $3 = emit_iftableitem($3, yylineno);
              check_arith($1, "%"); check_arith($3, "%");
              if ($1->type == constnum_e && $3->type == constnum_e) {
                  $$ = newexpr(arithexpr_e);
                  $$->numConst = ((int)$3->numConst != 0)
                                 ? (int)$1->numConst % (int)$3->numConst : 0;
                  $$->sym = newtemp();
                  emit(mod, $$, newexpr_constnum($1->numConst),
                       newexpr_constnum($3->numConst), -1, yylineno);
              } else {
                  $$ = newexpr(arithexpr_e);
                  $$->sym = istempexpr($1) ? $1->sym
                          : istempexpr($3) ? $3->sym
                          : newtemp();
                  emit(mod, $$, $1, $3, -1, yylineno);
              }
          }
      }

    /* ── Relational ── */
    | expr GREATER_THAN expr {
          PRINT_RULE("expr -> expr > expr");
          if (!$1 || !$3) { $$ = newexpr(boolexpr_e); yyerrok; }
          else {
              $1 = emit_iftableitem($1, yylineno);
              $3 = emit_iftableitem($3, yylineno);
              if ($1->type == boolexpr_e && !$1->sym) $1 = make_bool_expr($1, 1);
              if ($3->type == boolexpr_e && !$3->sym) $3 = make_bool_expr($3, 1);
              $$ = newexpr(boolexpr_e);
              emit(if_greater, NULL, $1, $3, -1, yylineno);
              emit(jump,       NULL, NULL, NULL, -1, yylineno);
              $$->truelist  = newlist(currQuad - 2);
              $$->falselist = newlist(currQuad - 1);
          }
      }
    | expr GREATER_EQUAL expr {
          PRINT_RULE("expr -> expr >= expr");
          if (!$1 || !$3) { $$ = newexpr(boolexpr_e); yyerrok; }
          else {
              $1 = emit_iftableitem($1, yylineno);
              $3 = emit_iftableitem($3, yylineno);
              if ($1->type == boolexpr_e && !$1->sym) $1 = make_bool_expr($1, 1);
              if ($3->type == boolexpr_e && !$3->sym) $3 = make_bool_expr($3, 1);
              $$ = newexpr(boolexpr_e);
              emit(if_greatereq, NULL, $1, $3, -1, yylineno);
              emit(jump,         NULL, NULL, NULL, -1, yylineno);
              $$->truelist  = newlist(currQuad - 2);
              $$->falselist = newlist(currQuad - 1);
          }
      }
    | expr LESS_THAN expr {
          PRINT_RULE("expr -> expr < expr");
          if (!$1 || !$3) { $$ = newexpr(boolexpr_e); yyerrok; }
          else {
              $1 = emit_iftableitem($1, yylineno);
              $3 = emit_iftableitem($3, yylineno);
              if ($1->type == boolexpr_e && !$1->sym) $1 = make_bool_expr($1, 1);
              if ($3->type == boolexpr_e && !$3->sym) $3 = make_bool_expr($3, 1);
              $$ = newexpr(boolexpr_e);
              emit(if_less, NULL, $1, $3, -1, yylineno);
              emit(jump,    NULL, NULL, NULL, -1, yylineno);
              $$->truelist  = newlist(currQuad - 2);
              $$->falselist = newlist(currQuad - 1);
          }
      }
    | expr LESS_EQUAL expr {
          PRINT_RULE("expr -> expr <= expr");
          if (!$1 || !$3) { $$ = newexpr(boolexpr_e); yyerrok; }
          else {
              $1 = emit_iftableitem($1, yylineno);
              $3 = emit_iftableitem($3, yylineno);
              if ($1->type == boolexpr_e && !$1->sym) $1 = make_bool_expr($1, 1);
              if ($3->type == boolexpr_e && !$3->sym) $3 = make_bool_expr($3, 1);
              $$ = newexpr(boolexpr_e);
              emit(if_lesseq, NULL, $1, $3, -1, yylineno);
              emit(jump,      NULL, NULL, NULL, -1, yylineno);
              $$->truelist  = newlist(currQuad - 2);
              $$->falselist = newlist(currQuad - 1);
          }
      }
    | expr EQUAL expr {
          PRINT_RULE("expr -> expr == expr");
          if (!$1 || !$3) { $$ = newexpr(boolexpr_e); yyerrok; }
          else {
              $1 = emit_iftableitem($1, yylineno);
              $3 = emit_iftableitem($3, yylineno);
              if ($1->type == boolexpr_e && !$1->sym) $1 = make_bool_expr($1, 1);
              if ($3->type == boolexpr_e && !$3->sym) $3 = make_bool_expr($3, 1);
              $$ = newexpr(boolexpr_e);
              emit(if_eq, NULL, $1, $3, -1, yylineno);
              emit(jump,  NULL, NULL, NULL, -1, yylineno);
              $$->truelist  = newlist(currQuad - 2);
              $$->falselist = newlist(currQuad - 1);
          }
      }
    | expr NOT_EQUAL expr {
          PRINT_RULE("expr -> expr != expr");
          if (!$1 || !$3) { $$ = newexpr(boolexpr_e); yyerrok; }
          else {
              $1 = emit_iftableitem($1, yylineno);
              $3 = emit_iftableitem($3, yylineno);
              if ($1->type == boolexpr_e && !$1->sym) $1 = make_bool_expr($1, 1);
              if ($3->type == boolexpr_e && !$3->sym) $3 = make_bool_expr($3, 1);
              $$ = newexpr(boolexpr_e);
              emit(if_noteq, NULL, $1, $3, -1, yylineno);
              emit(jump,     NULL, NULL, NULL, -1, yylineno);
              $$->truelist  = newlist(currQuad - 2);
              $$->falselist = newlist(currQuad - 1);
          }
      }

    /* ── Logical AND  (short-circuit via M marker) ── */
    | expr AND {
          /* convert left operand to boolexpr if needed */
          if ($1 && $1->type != boolexpr_e)
              $1 = make_bool_expr($1, 0);
      }
      M expr {
          if ($5 && $5->type != boolexpr_e)
              $5 = make_bool_expr($5, 0);
          $$ = newexpr(boolexpr_e);
          /* $1 true  →  evaluate $5  */
          patchlist($1->truelist, $4);
          $$->falselist = mergelist($1->falselist, $5->falselist);
          $$->truelist  = $5->truelist;
      }

    /* ── Logical OR  (short-circuit via M marker) ── */
    | expr OR {
          if ($1 && $1->type != boolexpr_e)
              $1 = make_bool_expr($1, 0);
      }
      M expr {
          if ($5 && $5->type != boolexpr_e)
              $5 = make_bool_expr($5, 0);
          $$ = newexpr(boolexpr_e);
          /* $1 false  →  evaluate $5  */
          patchlist($1->falselist, $4);
          $$->truelist  = mergelist($1->truelist, $5->truelist);
          $$->falselist = $5->falselist;
      }

    | term { $$ = $1; }
;

/* ═══════════════════════════════════════════════════════════
   term
   ═══════════════════════════════════════════════════════════ */
term:
      LEFT_PARENTHESIS expr RIGHT_PARENTHESIS {
          PRINT_RULE("term -> (expr)");
          $$ = $2;
      }
    | MINUS expr %prec UMINUS {
          PRINT_RULE("term -> -expr");
          if (!$2) { $$ = NULL; yyerrok; }
          else {
              check_arith($2, "unary minus");
              $$ = newexpr(arithexpr_e);
              $$->sym = istempexpr($2) ? $2->sym : newtemp();
              emit(uminus, $$, $2, NULL, -1, yylineno);
          }
      }
    | NOT expr {
          PRINT_RULE("term -> not expr");
          if (!$2) { $$ = NULL; yyerrok; }
          else {
              if ($2->type != boolexpr_e)
                  $2 = make_bool_expr($2, 0);
              $$ = newexpr(boolexpr_e);
              $$->truelist  = $2->falselist;   /* swap: NOT flips true/false */
              $$->falselist = $2->truelist;
          }
      }

    /* ── Pre-increment / Pre-decrement ── */
    | INCREMENT lvalue {
          PRINT_RULE("term -> ++lvalue");
          if (!$2 || !$2->sym) { $$ = NULL; yyerrok; }
          else {
              Symbol_t *sym = $2->sym;
              if (sym->type == USER_FUNC || sym->type == LIB_FUNC) {
                  printf("[SYNTAX ERROR] Cannot increment function '%s' at line %d\n",
                         sym->name, $2->sym->line);
                  syntax_errors++; $$ = NULL; yyerrok;
              } else {
                  check_arith($2, "++lvalue");
                  if ($2->type == tableitem_e) {
                      /* orig gets a new temp from emit_iftableitem;
                         reuse that same temp for the add result */
                      expr_t *orig = emit_iftableitem($2, yylineno);
                      emit(add, orig, orig, newexpr_constnum(1), -1, yylineno);
                      emit(tablesetelem, $2, $2->index, orig, -1, yylineno);
                      $$ = orig;
                  } else {
                      emit(add, $2, $2, newexpr_constnum(1), -1, yylineno);
                      $$ = newexpr(arithexpr_e);
                      $$->sym = newtemp();
                      emit(assign, $$, $2, NULL, -1, yylineno);
                  }
              }
          }
      }
    | lvalue INCREMENT {
          PRINT_RULE("term -> lvalue++");
          if (!$1 || !$1->sym) { $$ = NULL; yyerrok; }
          else {
              Symbol_t *sym = $1->sym;
              if (sym->type == USER_FUNC || sym->type == LIB_FUNC) {
                  printf("[SYNTAX ERROR] Cannot increment function '%s' at line %d\n",
                         sym->name, $1->sym->line);
                  syntax_errors++; $$ = NULL; yyerrok;
              } else {
                  check_arith($1, "lvalue++");
                  if ($1->type == tableitem_e) {
                      /* allocate res FIRST so it gets a lower temp number,
                         then emit_iftableitem for orig */
                      expr_t *res  = newexpr(var_e); res->sym = newtemp();
                      expr_t *orig = emit_iftableitem($1, yylineno);
                      emit(assign, res, orig, NULL, -1, yylineno);
                      emit(add, orig, orig, newexpr_constnum(1), -1, yylineno);
                      emit(tablesetelem, $1, $1->index, orig, -1, yylineno);
                      $$ = res;
                  } else {
                      expr_t *res = newexpr(var_e); res->sym = newtemp();
                      emit(assign, res, $1, NULL, -1, yylineno);
                      emit(add, $1, $1, newexpr_constnum(1), -1, yylineno);
                      $$ = res;
                  }
              }
          }
      }
    | DECREMENT lvalue {
          PRINT_RULE("term -> --lvalue");
          if (!$2 || !$2->sym) { $$ = NULL; yyerrok; }
          else {
              Symbol_t *sym = $2->sym;
              if (sym->type == USER_FUNC || sym->type == LIB_FUNC) {
                  printf("[SYNTAX ERROR] Cannot decrement function '%s' at line %d\n",
                         sym->name, $2->sym->line);
                  syntax_errors++; $$ = NULL; yyerrok;
              } else {
                  check_arith($2, "--lvalue");
                  if ($2->type == tableitem_e) {
                      expr_t *orig = emit_iftableitem($2, yylineno);
                      emit(sub, orig, orig, newexpr_constnum(1), -1, yylineno);
                      emit(tablesetelem, $2, $2->index, orig, -1, yylineno);
                      $$ = orig;
                  } else {
                      emit(sub, $2, $2, newexpr_constnum(1), -1, yylineno);
                      $$ = newexpr(arithexpr_e);
                      $$->sym = newtemp();
                      emit(assign, $$, $2, NULL, -1, yylineno);
                  }
              }
          }
      }
    | lvalue DECREMENT {
          PRINT_RULE("term -> lvalue--");
          if (!$1 || !$1->sym) { $$ = NULL; yyerrok; }
          else {
              Symbol_t *sym = $1->sym;
              if (sym->type == USER_FUNC || sym->type == LIB_FUNC) {
                  printf("[SYNTAX ERROR] Cannot decrement function '%s' at line %d\n",
                         sym->name, $1->sym->line);
                  syntax_errors++; $$ = NULL; yyerrok;
              } else {
                  check_arith($1, "lvalue--");
                  if ($1->type == tableitem_e) {
                      /* allocate res FIRST so it gets a lower temp number */
                      expr_t *res  = newexpr(var_e); res->sym = newtemp();
                      expr_t *orig = emit_iftableitem($1, yylineno);
                      emit(assign, res, orig, NULL, -1, yylineno);
                      emit(sub, orig, orig, newexpr_constnum(1), -1, yylineno);
                      emit(tablesetelem, $1, $1->index, orig, -1, yylineno);
                      $$ = res;
                  } else {
                      expr_t *res = newexpr(var_e); res->sym = newtemp();
                      emit(assign, res, $1, NULL, -1, yylineno);
                      emit(sub, $1, $1, newexpr_constnum(1), -1, yylineno);
                      $$ = res;
                  }
              }
          }
      }
    | primary { $$ = emit_iftableitem($1, yylineno); }
;

/* ═══════════════════════════════════════════════════════════
   assignexpr
   ═══════════════════════════════════════════════════════════ */
assignexpr:
      lvalue ASSIGN expr {
          PRINT_RULE("assignexpr -> lvalue = expr");
          if (!$1 || !$3) { $$ = NULL; yyerrok; }
          else if ($1->sym && accessViolation($1->sym)) {
              printf("[SYNTAX ERROR] Cannot access '%s' inside nested function at line %d\n",
                     $1->sym->name, yylineno);
              syntax_errors++; $$ = NULL; yyerrok;
          } else if ($1->sym &&
                     ($1->sym->type == USER_FUNC || $1->sym->type == LIB_FUNC)) {
              printf("[SYNTAX ERROR] Cannot assign to function '%s' at line %d\n",
                     $1->sym->name, yylineno);
              syntax_errors++; $$ = NULL; yyerrok;
          } else {
              /* materialise rhs boolean if needed */
              expr_t *rhs = $3;
              if (rhs->type == tableitem_e)
                  rhs = emit_iftableitem(rhs, yylineno);
              if (rhs->type == boolexpr_e && rhs->sym == NULL)
                  rhs = make_bool_expr(rhs, 1);

              if ($1->type == tableitem_e) {
                  emit(tablesetelem, $1, $1->index, rhs, -1, yylineno);
                  $$ = newexpr(assignexpr_e);
                  $$->sym = newtemp();
                  $$->index = $1->index;
                  emit(tablegetelem, $$, lvalue_expr($1->sym), $1->index, -1, yylineno);
              } else {
                  emit(assign, $1, rhs, NULL, -1, yylineno);
                  $$ = newexpr(assignexpr_e);
                  $$->sym = newtemp();
                  emit(assign, $$, $1, NULL, -1, yylineno);
              }
          }
      }
    | call ASSIGN expr {
          PRINT_RULE("assignexpr -> call = expr  [ERROR]");
          printf("[SYNTAX ERROR] Cannot assign to function call result at line %d\n",
                 $2->lineNumber);
          syntax_errors++;
          $$ = NULL; yyerrok;
      }
;

/* ═══════════════════════════════════════════════════════════
   primary / lvalue / member / call
   ═══════════════════════════════════════════════════════════ */
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
          if ($2) {
              expr_t *fe = newexpr(programfunc_e);
              fe->sym = $2;
              $$ = fe;
          } else { $$ = NULL; yyerrok; }
      }
    | const {
          PRINT_RULE("primary -> const");
          $$ = $1;
      }
;

lvalue:
      ID {
          PRINT_RULE("lvalue -> id");
          if (!$1) { $$ = NULL; yyerrok; }
          else {
              Symbol_t *sym = resolveSymbol($1->tokenContent, currentScope, 0);
              if (!sym) {
                  SymbolType t = (currentScope == 0) ? GLOBAL_VAR : LOCAL_VAR;
                  sym = insertSymbol($1->tokenContent, t, currentScope, $1->lineNumber);
              } else if (accessViolation(sym)) {
                  printf("[SYNTAX ERROR] Cannot access '%s' inside nested function at line %d\n",
                         $1->tokenContent, $1->lineNumber);
                  syntax_errors++;
              }
              $$ = sym ? lvalue_expr(sym) : NULL;
          }
      }
    | LOCAL ID {
          PRINT_RULE("lvalue -> local id");
          if (!$2) { $$ = NULL; yyerrok; }
          else {
              Symbol_t *sym = lookupSymbolInScope($2->tokenContent, currentScope);
              if (sym) {
                  if (sym->type == LOCAL_VAR || sym->type == USER_FUNC ||
                      sym->type == FORMAL_ARG)
                      $$ = lvalue_expr(sym);
                  else {
                      printf("[SYNTAX ERROR] 'local %s' conflicts with symbol in scope %d (line %d)\n",
                             $2->tokenContent, currentScope, $2->lineNumber);
                      syntax_errors++; $$ = NULL; yyerrok;
                  }
              } else {
                  if (isLibraryFunction($2->tokenContent)) {
                      printf("[SYNTAX ERROR] Cannot shadow library function '%s' with local (line %d)\n",
                             $2->tokenContent, $2->lineNumber);
                      syntax_errors++; $$ = NULL; yyerrok;
                  } else {
                      SymbolType t = (currentScope == 0) ? GLOBAL_VAR : LOCAL_VAR;
                      sym = insertSymbol($2->tokenContent, t, currentScope, $2->lineNumber);
                      $$ = lvalue_expr(sym);
                  }
              }
          }
      }
    | DOUBLE_COLON ID {
          PRINT_RULE("lvalue -> ::id");
          if (!$2) { $$ = NULL; yyerrok; }
          else {
              Symbol_t *sym = lookupSymbolInScope($2->tokenContent, 0);
              if (!sym) {
                  printf("[SYNTAX ERROR] Undefined global '::%s' at line %d\n",
                         $2->tokenContent, $2->lineNumber);
                  syntax_errors++; $$ = NULL; yyerrok;
              } else {
                  $$ = lvalue_expr(sym);
              }
          }
      }
    | member { $$ = $1; }
;

member:
      lvalue DOT ID {
          PRINT_RULE("member -> lvalue.id");
          if (!$1 || !$3) { $$ = NULL; yyerrok; }
          else {
              expr_t *base = emit_iftableitem($1, yylineno);
              $$ = member_item(base, $3->tokenContent);
          }
      }
    | lvalue LEFT_SQUARE_BRACKET expr RIGHT_SQUARE_BRACKET {
          PRINT_RULE("member -> lvalue[expr]");
          if (!$1 || !$3) { $$ = NULL; yyerrok; }
          else {
              $1 = emit_iftableitem($1, yylineno);
              $$ = newexpr(tableitem_e);
              $$->sym   = $1->sym;
              $$->index = $3;
          }
      }
    | call DOT ID {
          PRINT_RULE("member -> call.id");
          if (!$1 || !$3) { $$ = NULL; yyerrok; }
          else {
              $1 = emit_iftableitem($1, yylineno);
              $$ = member_item($1, $3->tokenContent);
          }
      }
    | call LEFT_SQUARE_BRACKET expr RIGHT_SQUARE_BRACKET {
          PRINT_RULE("member -> call[expr]");
          if (!$1 || !$3) { $$ = NULL; yyerrok; }
          else {
              $1 = emit_iftableitem($1, yylineno);
              $$ = newexpr(tableitem_e);
              $$->sym   = $1->sym;
              $$->index = $3;
          }
      }
;

call:
      call LEFT_PARENTHESIS elist RIGHT_PARENTHESIS {
          PRINT_RULE("call -> call(elist)");
          if (!$1) { $$ = NULL; yyerrok; }
          else $$ = make_call($1, reverse_expr_list($3));
      }
    | lvalue callsuffix {
          PRINT_RULE("call -> lvalue callsuffix");
          if (!$1) { $$ = NULL; yyerrok; }
          else if ($1->sym && accessViolation($1->sym)) {
              printf("[SYNTAX ERROR] Cannot access '%s' inside nested function at line %d\n",
                     $1->sym->name, yylineno);
              syntax_errors++; $$ = NULL; yyerrok;
          } else {
              $1 = emit_iftableitem($1, yylineno);
              if ($2.method) {
                  expr_t *method = member_item($1, $2.name);
                  if ($2.elist)
                      get_last($2.elist)->next = $1;
                  else
                      $2.elist = $1;
                  $1 = emit_iftableitem(method, yylineno);
              }
              $$ = make_call($1, reverse_expr_list($2.elist));
          }
      }
    | LEFT_PARENTHESIS funcdef RIGHT_PARENTHESIS
      LEFT_PARENTHESIS elist RIGHT_PARENTHESIS {
          PRINT_RULE("call -> (funcdef)(elist)");
          if (!$2) { $$ = NULL; yyerrok; }
          else {
              expr_t *fe = newexpr(programfunc_e);
              fe->sym = $2;
              $$ = make_call(fe, reverse_expr_list($5));
          }
      }
;

callsuffix:
      normcall   { PRINT_RULE("callsuffix -> normcall");   $$ = $1; }
    | methodcall { PRINT_RULE("callsuffix -> methodcall"); $$ = $1; }
;

normcall:
    LEFT_PARENTHESIS elist RIGHT_PARENTHESIS {
        PRINT_RULE("normcall -> (elist)");
        $$.elist  = $2;
        $$.method = 0;
        $$.name   = NULL;
    }
;

methodcall:
    DOUBLE_DOT ID LEFT_PARENTHESIS elist RIGHT_PARENTHESIS {
        PRINT_RULE("methodcall -> ..id(elist)");
        $$.elist  = $4;
        $$.method = 1;
        $$.name   = $2 ? strdup($2->tokenContent) : NULL;
    }
;

/* ── elist ─────────────────────────────────────────────── */
elist:
      /* empty */ { $$ = NULL; }
    | expr {
          insideExprList++;
          /* materialise boolean before passing as argument */
          if ($1 && $1->type == boolexpr_e &&
              $1->truelist.size > 0 && $1->falselist.size > 0) {
              $1 = make_bool_expr($1, 1);
          }
          $$ = $1;
          insideExprList--;
      }
    | elist COMMA expr {
          insideExprList++;
          if ($3 && $3->type == boolexpr_e &&
              $3->truelist.size > 0 && $3->falselist.size > 0) {
              $3 = make_bool_expr($3, 1);
          }
          if ($1) get_last($1)->next = $3;
          else    $1 = $3;
          $$ = $1;
          insideExprList--;
      }
;

/* ── objectdef ─────────────────────────────────────────── */
objectdef:
      LEFT_SQUARE_BRACKET elist RIGHT_SQUARE_BRACKET {
          PRINT_RULE("objectdef -> [elist]");
          $$ = newexpr(newtable_e);
          $$->sym = newtemp();
          emit(tablecreate, $$, NULL, NULL, -1, yylineno);
          expr_t *e = $2; int idx = 0;
          while (e) {
              emit(tablesetelem, $$, newexpr_constnum(idx++), e, -1, yylineno);
              e = e->next;
          }
      }
    | LEFT_SQUARE_BRACKET indexed RIGHT_SQUARE_BRACKET {
          PRINT_RULE("objectdef -> [indexed]");
          $$ = newexpr(newtable_e);
          $$->sym = newtemp();
          emit(tablecreate, $$, NULL, NULL, -1, yylineno);
          indexed_t *cur = $2;
          while (cur) {
              emit(tablesetelem, $$, cur->key, cur->value, -1, yylineno);
              cur = cur->next;
          }
      }
;

indexed:
      indexedelem                       { $$ = $1; }
    | indexedelem COMMA indexed         { $$ = $1; $$->next = $3; }
;

indexedelem:
    LEFT_BRACE expr COLON expr RIGHT_BRACE {
        PRINT_RULE("indexedelem -> {expr:expr}");
        $$ = malloc(sizeof(indexed_t));
        $$->key   = $2;
        $$->value = $4;
        $$->next  = NULL;
    }
;

/* ── const ─────────────────────────────────────────────── */
const:
      INTCON  { $$ = newexpr_constnum(atof($1->tokenContent)); }
    | REALCON { $$ = newexpr_constnum(atof($1->tokenContent)); }
    | STR     { $$ = newexpr_conststring($1->tokenContent);    }
    | NIL     { $$ = newexpr(nil_e);                           }
    | TRUE    { $$ = newexpr_constbool(1);                     }
    | FALSE   { $$ = newexpr_constbool(0);                     }
;

/* ═══════════════════════════════════════════════════════════
   block / funcbody
   ═══════════════════════════════════════════════════════════ */
block:
    LEFT_BRACE { currentScope++; }
    stmts
    RIGHT_BRACE {
        PRINT_RULE("block -> { stmts }");
        hideScope(currentScope);
        currentScope--;
        $$ = $3;
    }
;

/* funcbody does NOT touch currentScope (funcdef already did) */
/* We reuse 'block' grammar but give it a separate rule so
   funcdef can access the stmt list via $9 below.
   Actually we just inline it inside funcdef using block directly. */

/* ═══════════════════════════════════════════════════════════
   if / while / for
   ═══════════════════════════════════════════════════════════ */

/* ── ifprefix ─── */
ifprefix:
    IF LEFT_PARENTHESIS expr RIGHT_PARENTHESIS {
        PRINT_RULE("ifprefix -> if(expr)");
        if (!$3) {
            printf("[SYNTAX ERROR] Invalid condition in 'if' at line %d\n", yylineno);
            syntax_errors++; $$ = -1; yyerrok;
        } else {
            expr_t *cond = $3;
            if (cond->type == boolexpr_e && cond->sym == NULL)
                cond = make_bool_expr(cond, 1);
            emit(if_eq, NULL, cond, newexpr_constbool(1), nextquad() + 2, yylineno);
            $$ = nextquad();
            emit(jump, NULL, NULL, NULL, -1, yylineno);
        }
    }
;

/* ── elseprefix ─── */
elseprefix:
    ELSE {
        PRINT_RULE("elseprefix -> else");
        $$ = nextquad();
        emit(jump, NULL, NULL, NULL, -1, yylineno);
    }
;

/* ── ifstmt ─── */
ifstmt:
      ifprefix stmt {
          PRINT_RULE("ifstmt -> if(expr) stmt");
          if ($1 >= 0) patchlabel($1, nextquad());
          make_stmt(&$$);
          $$.breaklist = $2.breaklist;
          $$.contlist  = $2.contlist;
      }
    | ifprefix stmt elseprefix stmt {
          PRINT_RULE("ifstmt -> if(expr) stmt else stmt");
          if ($1 >= 0) patchlabel($1, $3 + 1);
          patchlabel($3, nextquad());
          make_stmt(&$$);
          $$.breaklist = mergelist($2.breaklist, $4.breaklist);
          $$.contlist  = mergelist($2.contlist,  $4.contlist);
      }
;

/* ── whilestart / whilecond ─── */
whilestart:
    WHILE { $$ = nextquad(); }
;

whilecond:
    LEFT_PARENTHESIS expr RIGHT_PARENTHESIS {
        PRINT_RULE("whilecond -> (expr)");
        if (!$2) {
            printf("[SYNTAX ERROR] Invalid condition in 'while' at line %d\n", yylineno);
            syntax_errors++; $$ = 0; yyerrok;
        } else {
            expr_t *e = $2;
            if (e->type == boolexpr_e && e->sym == NULL)
                e = make_bool_expr(e, 1);
            emit(if_eq, NULL, e, newexpr_constbool(1), nextquad() + 2, yylineno);
            $$ = nextquad();
            emit(jump, NULL, NULL, NULL, -1, yylineno);
        }
    }
;

/* ── loopstart / loopend / loopstmt ─── */
loopstart: /* empty */ { push_loopcounter(); };
loopend:   /* empty */ { pop_loopcounter();  };

loopstmt:
    loopstart stmt loopend {
        make_stmt(&$$);
        $$.breaklist  = $2.breaklist;
        $$.contlist   = $2.contlist;
        $$.returnlist = $2.returnlist;
    }
;

/* ── whilestmt ─── */
whilestmt:
    whilestart whilecond loopstmt {
        PRINT_RULE("whilestmt -> while(expr) stmt");
        emit(jump, NULL, NULL, NULL, $1, yylineno);   /* loop back  */
        patchlabel($2, nextquad());                   /* exit jump  */
        if ($3.breaklist.size > 0) patchlist($3.breaklist, nextquad());
        if ($3.contlist.size  > 0) patchlist($3.contlist,  $1);
        make_stmt(&$$);
        $$.breaklist = emptylist();
        $$.contlist  = emptylist();
    }
;

/* ── forprefix ─── */
forprefix:
    FOR LEFT_PARENTHESIS elist SEMICOLON M expr SEMICOLON {
        PRINT_RULE("forprefix -> for(elist; M expr;");
        if (!$6) {
            printf("[SYNTAX ERROR] Invalid condition in 'for' at line %d\n", yylineno);
            syntax_errors++;
            $$.test  = $5;
            $$.enter = nextquad();
            yyerrok;
        } else {
            expr_t *cond = $6;
            if (cond->type == boolexpr_e && cond->sym == NULL)
                cond = make_bool_expr(cond, 1);
            $$.test  = $5;
            $$.enter = nextquad();
            emit(if_eq, NULL, cond, newexpr_constbool(1), -1, yylineno);
        }
    }
;

/* ── forstmt ─── */
forstmt:
    forprefix N elist RIGHT_PARENTHESIS N loopstmt N {
        PRINT_RULE("forstmt -> for(elist;expr;elist) stmt");
        /*
         *  $1 = forprefix  ($1.test, $1.enter)
         *  $2 = N1  (false-exit jump, emitted right after if_eq)
         *  $3 = elist2 (increment expressions)
         *  $5 = N2  (loop-back jump, after increment)
         *  $6 = loopstmt
         *  $7 = N3  (closure jump at end of body)
         *
         *  Connections (matching the slides):
         *    if_eq true  → body        : patchlabel($1.enter, $5+1)
         *    if_eq false → exit        : patchlabel($2,       nextquad())
         *    N2 loop back to test      : patchlabel($5,       $1.test)
         *    N3 closure → increment    : patchlabel($7,       $2+1)
         */
        patchlabel($1.enter, $5 + 1);    /* true jump  → body        */
        patchlabel($2,       nextquad());/* false jump → exit        */
        patchlabel($5,       $1.test);   /* loop jump  → test        */
        patchlabel($7,       $2 + 1);    /* closure    → increment   */

        if ($6.breaklist.size > 0) patchlist($6.breaklist, nextquad());
        if ($6.contlist.size  > 0) patchlist($6.contlist,  $2 + 1);

        make_stmt(&$$);
        $$.breaklist = emptylist();
        $$.contlist  = emptylist();
    }
;

/* ═══════════════════════════════════════════════════════════
   returnstmt
   ═══════════════════════════════════════════════════════════ */
returnstmt:
      RETURN SEMICOLON {
          PRINT_RULE("returnstmt -> return ;");
          make_stmt(&$$);
          if (functionDepth == 0) {
              printf("[SYNTAX ERROR] 'return' outside function at line %d\n",
                     $1->lineNumber);
              syntax_errors++;
          } else {
              emit(ret, NULL, NULL, NULL, -1, yylineno);
              int j = nextquad();
              emit(jump, NULL, NULL, NULL, -1, yylineno);
              $$.returnlist = newlist(j);
          }
      }
    | RETURN expr SEMICOLON {
          PRINT_RULE("returnstmt -> return expr ;");
          make_stmt(&$$);
          if (functionDepth == 0) {
              printf("[SYNTAX ERROR] 'return' outside function at line %d\n",
                     $1->lineNumber);
              syntax_errors++;
          } else if ($2) {
              expr_t *rv = emit_iftableitem($2, yylineno);
              if (rv->type == boolexpr_e && rv->sym == NULL &&
                  !(rv->truelist.size == 0 && rv->falselist.size == 0))
                  rv = make_bool_expr(rv, 1);
              emit(ret, rv, NULL, NULL, -1, yylineno);
              int j = nextquad();
              emit(jump, NULL, NULL, NULL, -1, yylineno);
              $$.returnlist = newlist(j);
          }
      }
;

/* ═══════════════════════════════════════════════════════════
   funcdef / funcprefix / idlist / idseq
   ═══════════════════════════════════════════════════════════ */
funcdef:
      FUNCTION funcprefix
      LEFT_PARENTHESIS { currentScope++; resetformalargsoffset(); }
      idlist {
          if ($2) attachFormalsToFunction($2, currentScope);
          --currentScope;
          enterscopespace();          /* FUNCTION_LOCAL */
          resetfunctionlocalsoffset();
          functionDepth++;
          /* save enclosing return-list */
          retListStack[++retListTop] = retList;
          retList = emptylist();
      }
      RIGHT_PARENTHESIS
      block {
          PRINT_RULE("funcdef -> function id(idlist) block");
          functionDepth--;
          if (!$2) { $$ = NULL; yyerrok; }
          else {
              Symbol_t *f = $2;
              /* patch return jumps → funcend */
              retList = $8.returnlist;
              if (retList.size > 0)
                  patchlist(retList, nextquad());
              f->totallocals = currscopeoffset();
              emit(funcend, lvalue_expr(f), NULL, NULL, -1, yylineno);
              /* patch entry jump immediately after funcend */
              patchlabel(jumpStack[jumpStackTop--], nextquad());
              /* restore enclosing state */
              exitscopespace();          /* leave FUNCTION_LOCAL */
              int saved = popscopeoffset();
              restorecurrscopeoffset(saved);
              retList  = retListStack[retListTop--];
              funcSym  = (funcSymTop >= 0) ? funcSymStack[funcSymTop--] : NULL;
              lcs_top  = saved_lcs_top;
              $$ = f;
          }
      }

    | FUNCTION LEFT_PARENTHESIS {
          /* Anonymous function */
          char tmp[32];
          sprintf(tmp, "$%d", anonFuncCounter++);
          saved_lcs_top = lcs_top; lcs_top = NULL;
          funcSymStack[++funcSymTop] = funcSym;
          Symbol_t *anon = insertSymbol(tmp, USER_FUNC, currentScope, yylineno);
          funcSym = anon;
          jumpStack[++jumpStackTop] = nextquad();
          emit(jump, NULL, NULL, NULL, -1, yylineno);
          emit(funcstart, lvalue_expr(funcSym), NULL, NULL, -1, yylineno);
          funcSym->iaddress = currQuad - 1;
          pushscopeoffset(currscopeoffset());
          enterscopespace();           /* FORMAL_ARG */
          currentScope++;
          resetformalargsoffset();
      }
      idlist {
          char tmp[32];
          sprintf(tmp, "$%d", anonFuncCounter - 1);
          Symbol_t *anon = lookupSymbolInScope(tmp, currentScope - 1);
          if (anon) attachFormalsToFunction(anon, currentScope);
          --currentScope;
          enterscopespace();           /* FUNCTION_LOCAL */
          resetfunctionlocalsoffset();
          functionDepth++;
          retListStack[++retListTop] = retList;
          retList = emptylist();
      }
      RIGHT_PARENTHESIS
      block {
          PRINT_RULE("funcdef -> function(idlist) block");
          functionDepth--;
          Symbol_t *f = funcSym;
          if (!f) { $$ = NULL; yyerrok; }
          else {
              retList = $7.returnlist;
              if (retList.size > 0)
                  patchlist(retList, nextquad());
              f->totallocals = currscopeoffset();
              emit(funcend, lvalue_expr(f), NULL, NULL, -1, yylineno);
              /* patch entry jump immediately after funcend */
              patchlabel(jumpStack[jumpStackTop--], nextquad());
              exitscopespace();
              exitscopespace();
              int saved = popscopeoffset();
              restorecurrscopeoffset(saved);
              retList  = retListStack[retListTop--];
              funcSym  = (funcSymTop >= 0) ? funcSymStack[funcSymTop--] : NULL;
              lcs_top  = saved_lcs_top;
              $$ = f;
          }
      }
;

funcprefix:
    ID {
        PRINT_RULE("funcprefix -> id");
        saved_lcs_top = lcs_top; lcs_top = NULL;
        funcSymStack[++funcSymTop] = funcSym;

        if (isLibraryFunction($1->tokenContent)) {
            printf("[SYNTAX ERROR] Cannot redefine library function '%s' (line %d)\n",
                   $1->tokenContent, $1->lineNumber);
            syntax_errors++; $$ = NULL; yyerrok;
            funcSym = NULL;
        } else if (lookupSymbolInScope($1->tokenContent, currentScope)) {
            printf("[SYNTAX ERROR] Symbol '%s' already declared in scope %d (line %d)\n",
                   $1->tokenContent, currentScope, $1->lineNumber);
            syntax_errors++; $$ = NULL; yyerrok;
            funcSym = NULL;
        } else {
            Symbol_t *f = insertSymbol($1->tokenContent, USER_FUNC,
                                       currentScope, $1->lineNumber);
            funcSym = f;
            /* emit entry jump + funcstart */
            jumpStack[++jumpStackTop] = nextquad();
            emit(jump, NULL, NULL, NULL, -1, yylineno);
            emit(funcstart, lvalue_expr(f), NULL, NULL, -1, yylineno);
            f->iaddress = currQuad - 1;
            pushscopeoffset(currscopeoffset());
            enterscopespace();        /* FORMAL_ARG */
            $$ = f;
        }
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
              Symbol_t *s = insertSymbol($1->tokenContent, FORMAL_ARG,
                                         currentScope, $1->lineNumber);
              incurrscopeoffset();
              (void)s;
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
              Symbol_t *s = insertSymbol($3->tokenContent, FORMAL_ARG,
                                         currentScope, $3->lineNumber);
              incurrscopeoffset();
              (void)s;
          }
      }
;

%%

/* ═══════════════════════════════════════════════════════════
   yylex  (unchanged from Phase-2 parser)
   ═══════════════════════════════════════════════════════════ */
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
