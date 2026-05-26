#ifndef INTERMEDIATE_CODE_H
#define INTERMEDIATE_CODE_H
#include "Phase2Functions.h"





extern int functionLocalOffset;
extern int savedLocalOffset;







typedef enum iopcode {  // As described at [PDF 9], Slide 37/54.
    assign,
    add,
    sub,
    mul,
    divide,
    mod,
    uminus,
    and,
    or,
    not_,
    if_eq,
    if_noteq,
    if_lesseq,
    if_greatereq,
    if_less,
    if_greater,
    jump,
    call,
    param,
    ret,
    getretval,
    funcstart,
    funcend,
    tablecreate,
    tablegetelem,
    tablesetelem,
    nop,
    not_used
} iopcode;



typedef struct quad {  // As described at [PDF 9], Slide 37/54.
    iopcode     op;
    struct expr* result;
    struct expr* arg1;
    struct expr* arg2;
    int    label;
    int    line;
    int   taddress;
}quad;

extern quad* quads;



typedef struct Lc_stack_t {/* As described at [PDF 11], Slide 22/26. */
    struct Lc_stack_t* next;
    int counter;
} Lc_stack_t;

typedef enum { // As described at [PDF 10], Slide 17/38.
    var_e, tableitem_e, programfunc_e, libraryfunc_e,
    arithexpr_e, boolexpr_e, assignexpr_e,
    constnum_e, constbool_e, conststring_e,
    nil_e, newtable_e
} expr_cat;

typedef struct {
    int* items;
    int size;
} IntList;

typedef struct expr {// As described at [PDF 10], Slide 17/38.
    expr_cat type;
    Symbol_t* sym;
    struct expr* index;
    double numConst;
    char* strConst;
    unsigned char boolConst;
    struct expr* next;
    IntList truelist;
    IntList falselist;
} expr_t;

typedef struct call {// As described at [PDF 10], Slide 28/38.
    struct expr* elist;
    unsigned char method;
    char* name;
} call_t;

typedef struct indexed {
    struct expr* key;
    struct expr* value;
    struct indexed* next;
}indexed_t;

typedef struct stmt_t {//As described at [PDF 11], Slide 26/26.
    IntList breaklist;
    IntList contlist;
    IntList returnlist;
} stmt_t;

typedef struct forprefix_t {//As described at [PDF 11], Slide 17/26.
    int test;
    int enter;
} forprefix_t;

typedef struct callstruct_t {
    struct expr* elist;
    unsigned char method;
    char* name;
} callstruct_t;






// Συναρτήσεις όπως αναφέρονται στις Διαλέξεις και κάποιες άλλες custom που αφορούν την Phase 3.

void emit(iopcode op, expr_t* result, expr_t* arg1, expr_t* arg2, int label, int line);
int currscope(void);
void resettemp(void);
scopespace_t currscopespace(void);
int currscopeoffset(void);
void incurrscopeoffset(void);
void enterscopespace(void);
void exitscopespace(void);
void resetformalargsoffset(void);
void pushscopeoffset(int offset);
int popscopeoffset(void);
int nextquadlabel(void);
void restorecurrscopeoffset(int n);
expr_t* lvalue_expr(Symbol_t* sym);
char* newtempfuncname(void);
void patchlabel(int quadNo, int label);
void resetfunctionlocalsoffset(void);
expr_t* newexpr(expr_cat t);
expr_t* newexpr_conststring(const char* s);
expr_t* newexpr_constnum(double n);
expr_t* newexpr_constbool( int b);
void emit_assign(expr_t* target, expr_t* value, int line);
expr_t* emit_iftableitem(expr_t* e, int line);
expr_t* member_item(expr_t* lv, char* name);
Symbol_t* newtemp(void);
expr_t* make_call(expr_t* lv,expr_t* reversed_elist);
expr_t* get_last(expr_t* list);
const char* opcode_to_string(iopcode op);
const char* expr_to_str(expr_t* e);
void check_arith(expr_t* e, const char* context);
int istempexpr(expr_t* e);
int istempname(char* s);
int nextquad(void);
void make_stmt (struct stmt_t* s);
IntList emptylist(void);
IntList newlist(int i);
IntList mergelist(IntList a, IntList b);
void patchlist(IntList list, int label) ;
void push_loopcounter(void);
void pop_loopcounter(void);
int inLoop(void);
void printQuads();
void  expr_to_buf(expr_t* e, char* out, size_t size);
void merge_jumps();
expr_t* make_bool_expr(expr_t* e, int patch_now);
int isIllegalAccess(Symbol_t* sym);
int isTempName(const char* name);
expr_t* reverse_expr_list(expr_t* head);
void verify_symbol_table(void);


#endif // INTERMEDIATE_CODE_H