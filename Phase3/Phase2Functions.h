
#ifndef PHASE2_FUNCTIONS_H
#define PHASE2_FUNCTIONS_H

#define MAX_SCOPE 1000

/* Symbol types */
typedef enum {
    GLOBAL_VAR,
    LOCAL_VAR,
    FORMAL_ARG,
    USER_FUNC,
    LIB_FUNC
} SymbolType;


typedef enum scopespace_t {
    scopespace_undef = -1,
    programvar,
    functionlocal,
    formalarg
} scopespace_t;

/* Formal argument list node */
typedef struct FormalArg {
    char *name;
    int   line;
    int   scope;
    struct FormalArg *next;
} FormalArg;

/* Symbol table entry */
typedef struct Symbol_t {
    char        *name;
    SymbolType   type;
    int          scope;
    int          line;
    int          active;
    int          funcDepth;
    struct Symbol_t *next;
    FormalArg   *formalList;
    int          formal_count;
    scopespace_t space;
    int          offset;
    int          iaddress;
    int          totallocals;
} Symbol_t;


extern Symbol_t *scope_table[MAX_SCOPE];


Symbol_t *insertSymbol(const char *name, SymbolType type, int scope, int line);
void      hideScope(int scope);
Symbol_t *lookupSymbolInScope(const char *name, int scope);
Symbol_t *lookupGlobalSymbol(const char *name);
Symbol_t *resolveSymbol(const char *name, int currentScope, int forceGlobal);
void      attachFormalsToFunction(Symbol_t *func, int scope);


Symbol_t *newsymbol(const char *name, SymbolType type);
int       isLibraryFunction(const char *name);
void      initLibraryFunctions(void);
void      printSymbolTable(void);


scopespace_t currscopespace(void);
void         enterscopespace(void);
void         exitscopespace(void);
int          currscopeoffset(void);
void         incurrscopeoffset(void);
void         resetformalargsoffset(void);
void         pushscopeoffset(int offset);
int          popscopeoffset(void);
int          currscope(void);
void         resettemp(void);
Symbol_t    *newtemp(void);

#endif /* PHASE2_FUNCTIONS_H */
