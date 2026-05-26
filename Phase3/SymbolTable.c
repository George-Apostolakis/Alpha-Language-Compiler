#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "SymbolTable.h"
#include "alpha_lexer.h"

Symbol_t *scope_table[MAX_SCOPE] = {0};
extern int syntax_errors;
extern int currentScope;
extern int yylineno;
extern int functionDepth;

Symbol_t* insertSymbol(const char* name, SymbolType type, int scope, int line) {
    Symbol_t *sym = malloc(sizeof(Symbol_t));
    if (!sym) return NULL;

    sym->name = strdup(name);
    sym->type = type;
    sym->scope = scope;
    sym->line = line;
    sym->active = 1;
    sym->formalList = NULL;
    sym->formal_count = 0;
    sym->funcDepth = functionDepth;

    if (type == FORMAL_ARG) sym->funcDepth = functionDepth + 1;

    sym->next = NULL;

    if (scope_table[scope] == NULL) {
        scope_table[scope] = sym;
    } else {
        Symbol_t* curr = scope_table[scope];
        while (curr->next != NULL)
            curr = curr->next;
        curr->next = sym;
    }

    return sym;
}


void hideScope(int scope) {
    if (scope < 0 || scope >= MAX_SCOPE) {
        fprintf(stderr, "[FATAL] Invalid scope index %d\n", scope);
        exit(1);
    }

    Symbol_t *sym = scope_table[scope];

    if (!sym) return;

    while (sym) {
        sym->active = 0;
        sym = sym->next;
    }
}


Symbol_t* lookupSymbolInScope(const char* name, int scope) {
    if (scope < 0 || scope >= MAX_SCOPE)
        return NULL;

    Symbol_t* sym = scope_table[scope];

    while (sym) {
        if (sym->active && strcmp(sym->name, name) == 0)
            return sym;
        sym = sym->next;
    }

    return NULL;
}


Symbol_t *lookupGlobalSymbol(const char *name) {
    return lookupSymbolInScope(name, 0);
}


Symbol_t* resolveSymbol(const char* name, int currentScope, int forceGlobal) {
    if (forceGlobal) {
        return lookupSymbolInScope(name, 0);
    }

    Symbol_t* temp = scope_table[currentScope];
    while (temp) {
        if (temp->active && strcmp(temp->name, name) == 0) {
            if (temp->type == LOCAL_VAR || temp->type == FORMAL_ARG)
                return temp;
        }
        temp = temp->next;
    }

    for (int s = currentScope - 1; s >= 1; s--) {
        temp = scope_table[s];
        while (temp) {
            if (temp->active && strcmp(temp->name, name) == 0 &&
               (temp->type == LOCAL_VAR || temp->type == FORMAL_ARG || temp->type == USER_FUNC))
                return temp;
            temp = temp->next;
        }
    }

    temp = scope_table[0];
    while (temp) {
        if (temp->active && strcmp(temp->name, name) == 0)
            return temp;
        temp = temp->next;
    }

    return NULL;
}


void attachFormalsToFunction(Symbol_t *func, int scope) {
    if (!func) return;

    Symbol_t *temp = scope_table[scope];

    FormalArg *iter = func->formalList;
    while (iter) {
        FormalArg *next = iter->next;
        free(iter->name);
        free(iter);
        iter = next;
    }
    func->formalList = NULL;
    func->formal_count = 0;

    FormalArg *last = NULL;

    while (temp) {
        if (temp->type == LIB_FUNC) {
            printf("[SYNTAX ERROR] Cannot use as arguments, LIBRARY FUNCTIONS (line %d) \n", temp->line);
            syntax_errors++;
            temp = temp->next;
            continue;
        }

        if (temp->type == FORMAL_ARG && temp->active) {
            FormalArg *newFormal = malloc(sizeof(FormalArg));
            newFormal->name = strdup(temp->name);
            newFormal->scope = temp->scope;
            newFormal->line = temp->line;
            newFormal->next = NULL;

            if (!func->formalList) {
                func->formalList = newFormal;
                last = newFormal;
            } else {
                last->next = newFormal;
                last = newFormal;
            }

            func->formal_count++;
        }

        temp = temp->next;
    }
}

Symbol_t* newsymbol(const char* name, SymbolType type) {
    Symbol_t *sym = insertSymbol(name, type, currentScope, yylineno);
    return sym;
}