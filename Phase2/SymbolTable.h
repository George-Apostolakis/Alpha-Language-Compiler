#ifndef SYMBOL_TABLE_H
#define SYMBOL_TABLE_H
#define MAX_SCOPE 1000

typedef enum {
    GLOBAL_VAR,
    LOCAL_VAR,
    FORMAL_ARG,
    USER_FUNC,
    LIB_FUNC
} SymbolType;

typedef struct Symbol_t {
    char *name;
    SymbolType type;
    int scope;
    int line;
    int active;
    int funcDepth;
    struct Symbol_t *next;
    struct FormalArg *formalList;
    int formal_count;
} Symbol_t;

typedef struct FormalArg {
    char *name;
    int line;
    int scope;
    struct FormalArg *next;
} FormalArg;


extern Symbol_t *scope_table[MAX_SCOPE];

Symbol_t* insertSymbol(const char* name, SymbolType type, int scope, int line);

void hideScope(int scope);

Symbol_t *lookupSymbolInScope(const char *name, int scope);

Symbol_t *lookupGlobalSymbol(const char *name);

Symbol_t *resolveSymbol(const char *name, int currentScope, int forceGlobal);

void attachFormalsToFunction(Symbol_t *func, int scope);

Symbol_t* newsymbol(const char* name, SymbolType type);

#endif