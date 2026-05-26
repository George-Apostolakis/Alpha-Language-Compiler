
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include "alpha_lexer.h"
#include "Phase2Functions.h"

#define SCOPE_STACK_SIZE 100

/* Globals */
Symbol_t *scope_table[MAX_SCOPE] = {0};

extern int syntax_errors;
extern int currentScope;
extern int yylineno;
extern int functionDepth;
extern FILE *output_file;
extern int scopeSpaceCounter;

static int tempCounter        = 0;
int programVarOffset           = 0;
int formalArgOffset             = 0;
int functionLocalOffset         = 0;
static int scopeoffsetstack[SCOPE_STACK_SIZE];
static int top = -1;

/* Core symbol-table operations */

Symbol_t *insertSymbol(const char *name, SymbolType type, int scope, int line) {
    Symbol_t *sym = malloc(sizeof(Symbol_t));
    if (!sym) return NULL;

    sym->name         = strdup(name);
    sym->type         = type;
    sym->scope        = scope;
    sym->line         = line;
    sym->active       = 1;
    sym->formalList   = NULL;
    sym->formal_count = 0;
    sym->funcDepth    = functionDepth;
    sym->space        = scopespace_undef;
    sym->offset       = 0;
    sym->iaddress     = 0;
    sym->totallocals  = 0;
    sym->next         = NULL;

    if (type == FORMAL_ARG)
        sym->funcDepth = functionDepth + 1;

    /* Append to the end of the scope's linked list */
    if (scope_table[scope] == NULL) {
        scope_table[scope] = sym;
    } else {
        Symbol_t *cur = scope_table[scope];
        while (cur->next) cur = cur->next;
        cur->next = sym;
    }
    return sym;
}

void hideScope(int scope) {
    if (scope < 0 || scope >= MAX_SCOPE) return;
    for (Symbol_t *sym = scope_table[scope]; sym; sym = sym->next)
        sym->active = 0;
}

Symbol_t *lookupSymbolInScope(const char *name, int scope) {
    if (scope < 0 || scope >= MAX_SCOPE) return NULL;
    for (Symbol_t *sym = scope_table[scope]; sym; sym = sym->next)
        if (sym->active && strcmp(sym->name, name) == 0)
            return sym;
    return NULL;
}

Symbol_t *lookupGlobalSymbol(const char *name) {
    return lookupSymbolInScope(name, 0);
}

Symbol_t *resolveSymbol(const char *name, int curScope, int forceGlobal) {
    if (forceGlobal)
        return lookupSymbolInScope(name, 0);

    /* Step 1 — current scope, any active symbol */
    for (Symbol_t *s = scope_table[curScope]; s; s = s->next)
        if (s->active && strcmp(s->name, name) == 0)
            return s;

    /* Step 2 — intermediate scopes  */
    for (int sc = curScope - 1; sc >= 1; sc--)
        for (Symbol_t *s = scope_table[sc]; s; s = s->next)
            if (s->active && strcmp(s->name, name) == 0)
                return s;

    /* Step 3 — global scope */
    for (Symbol_t *s = scope_table[0]; s; s = s->next)
        if (s->active && strcmp(s->name, name) == 0)
            return s;

    return NULL;
}

void attachFormalsToFunction(Symbol_t *func, int scope) {
    if (!func) return;

    /* Free old list */
    FormalArg *iter = func->formalList;
    while (iter) { FormalArg *nx = iter->next; free(iter->name); free(iter); iter = nx; }
    func->formalList = NULL;
    func->formal_count = 0;

    FormalArg *last = NULL;
    for (Symbol_t *tmp = scope_table[scope]; tmp; tmp = tmp->next) {
        if (tmp->type == LIB_FUNC) {
            printf("[SYNTAX ERROR] Library function '%s' cannot be a formal (line %d)\n",
                   tmp->name, tmp->line);
            syntax_errors++;
            continue;
        }
        if (tmp->type == FORMAL_ARG && tmp->active) {
            FormalArg *f = malloc(sizeof(FormalArg));
            f->name  = strdup(tmp->name);
            f->scope = tmp->scope;
            f->line  = tmp->line;
            f->next  = NULL;
            if (!func->formalList) func->formalList = f; else last->next = f;
            last = f;
            func->formal_count++;
        }
    }
}

Symbol_t *newsymbol(const char *name, SymbolType type) {
    return insertSymbol(name, type, currentScope, yylineno);
}

/* Library functions */

static const char *libfunc_names[] = {
    "print", "input", "objectmemberkeys", "objecttotalmembers",
    "objectcopy", "totalarguments", "argument", "typeof",
    "strtonum", "sqrt", "cos", "sin"
};
#define NUM_LIBFUNCS (sizeof(libfunc_names) / sizeof(libfunc_names[0]))

int isLibraryFunction(const char *name) {
    for (int i = 0; i < (int)NUM_LIBFUNCS; i++)
        if (strcmp(name, libfunc_names[i]) == 0) return 1;
    return 0;
}

void initLibraryFunctions(void) {
    for (int i = 0; i < (int)NUM_LIBFUNCS; i++)
        insertSymbol(libfunc_names[i], LIB_FUNC, 0, 0);
}

/* Print symbol table */

void printSymbolTable(void) {
    fprintf(output_file, "\n==================== SYMBOL TABLE ====================\n");

    for (int s = 0; s < MAX_SCOPE; s++) {
        Symbol_t *sym = scope_table[s];
        if (!sym) continue;

        fprintf(output_file, "------------ Scope #%d ------------\n", s);
        while (sym) {
            const char *typeStr = "";
            switch (sym->type) {
                case GLOBAL_VAR: typeStr = "global variable"; break;
                case LOCAL_VAR:  typeStr = "local variable";  break;
                case FORMAL_ARG: typeStr = "formal argument"; break;
                case USER_FUNC:  typeStr = "user function";   break;
                case LIB_FUNC:   typeStr = "library function"; break;
            }
            fprintf(output_file, "\"%s\" [%s] (line %d) (scope %d)\n",
                    sym->name, typeStr, sym->line, sym->scope);
            sym = sym->next;
        }
    }
    fprintf(output_file, "==================================================\n");
}

/* Phase 3 prep — scope-space */

int currscope(void) { return currentScope; }

void resettemp(void) { tempCounter = 0; }

Symbol_t *newtemp(void) {
    char buf[64];
    sprintf(buf, "_t%u", tempCounter);
    Symbol_t *sym = lookupSymbolInScope(buf, currscope());
    if (sym) return sym;
    sym = insertSymbol(buf, LOCAL_VAR, currscope(), yylineno);
    tempCounter++;
    return sym;
}

scopespace_t currscopespace(void) {
    if (scopeSpaceCounter == 1) return programvar;
    if (scopeSpaceCounter % 2 == 0) return formalarg;
    return functionlocal;
}

int currscopeoffset(void) {
    switch (currscopespace()) {
        case programvar:     return programVarOffset;
        case functionlocal:  return functionLocalOffset;
        case formalarg:      return formalArgOffset;
        default: assert(0); return -1;
    }
}

void incurrscopeoffset(void) {
    switch (currscopespace()) {
        case programvar:    ++programVarOffset;      break;
        case functionlocal: ++functionLocalOffset;   break;
        case formalarg:     ++formalArgOffset;        break;
        default: assert(0);
    }
}

void enterscopespace(void) { ++scopeSpaceCounter; }
void exitscopespace(void)  {
    assert(scopeSpaceCounter > 1);
    --scopeSpaceCounter;
}

void resetformalargsoffset(void) { formalArgOffset = 0; }

void pushscopeoffset(int offset) {
    assert(top < SCOPE_STACK_SIZE - 1);
    scopeoffsetstack[++top] = offset;
}

int popscopeoffset(void) {
    assert(top >= 0);
    return scopeoffsetstack[top--];
}
