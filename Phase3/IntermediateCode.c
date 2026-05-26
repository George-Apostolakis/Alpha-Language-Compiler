#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "IntermediateCode.h"
#include "Phase2Functions.h"

#include <assert.h>

#define EXPAND_SIZE 1024
#define CURR_SIZE (total_quads)
#define NEW_SIZE (total_quads + EXPAND_SIZE)
#define SCOPE_STACK_SIZE 100


quad* quads = NULL;  // Πίνακας quads
static int total_quads = 0;
 int currQuad = 0;
static int tempCounter = 0;
extern int currentScope;
extern int scopeSpaceCounter;
int programVarOffset = 0;
int formalArgOffset = 0;
int savedLocalOffset = 0;
int functionLocalOffset = 0;
extern int yylineno;
static int scopeoffsetstack[SCOPE_STACK_SIZE];
static int top = -1;
extern int functionDepth;
extern int insideExprList;
extern Symbol_t* funcSymStack;
extern int  funcSymTop;



 Lc_stack_t* lcs_top = NULL;
 Lc_stack_t* lcs_bottom = NULL;

static void init_quad(struct quad* q) {
    q->op    = not_used;   // Not used yet.
    q->label = -1;           // Initial value
    q->taddress=-1;         // Initial value
    q->result  = NULL;
    q->arg1    = NULL;
    q->arg2    = NULL;

}

static void expand(void) { // As described at [PDF 9], Slide 38/54. - Επαύξηση μεγέθους του πίνακα των quads.
    size_t old_size = total_quads;
    size_t new_size = (quads == NULL) ? EXPAND_SIZE : old_size + EXPAND_SIZE;


    if (quads == NULL) {
        quads = calloc(new_size, sizeof(quad));
    } else {
        quad* tmp = realloc(quads, new_size * sizeof(quad));
        if (!tmp) {
            fprintf(stderr, "[FATAL] realloc failed for quads\n");
            exit(1);
        }
        quads = tmp;


        memset(quads + old_size, 0,(new_size - old_size) * sizeof(quad));

    }
    if (!quads) {
        fprintf(stderr, "[FATAL] allocation failed for quads\n");
        exit(1);
    }


    for (size_t i = old_size; i < new_size; ++i)
        init_quad(&quads[i]);

    total_quads = new_size;
}


void emit(iopcode op, expr_t * result, expr_t* arg1, expr_t* arg2, int label, int line) {// As described at [PDF 9], Slide 38/54. - Συνάρτηση παραγωγής quads.
    if (currQuad == CURR_SIZE) expand();
    //printf("[EMIT] quad[%d] opcode=%d label=%d (line %d)\n", currQuad+1, op, label+1, line);
    //printf("[EMIT] #%d: op=%d label=%d \n ", currQuad+1,op,label+1);
    if (op == assign && label != -1) {
        printf("[WARNING] emit(assign, ...) called with label = %d at line %d\n", label, line);
    }

    quads[currQuad].op = op;
    quads[currQuad].result = result;
    quads[currQuad].arg1 = arg1;
    quads[currQuad].arg2 = arg2;
    quads[currQuad].label = label;
    quads[currQuad].line = line;
    quads[currQuad].taddress = -1;
    currQuad++;
}



int currscope(void) {// As described at [PDF 9], Slide 45/54.
    return currentScope;
}

void resettemp(void) { // As described at [PDF 9], Slide 45/54.
    //printf("[RESETTEMP DEBUG] Function resettemp() called from line %d \n",yylineno );
    tempCounter = 0;
}


Symbol_t* newtemp() { // As described at [PDF 9], Slide 45/54.

    char tempname[64];
    sprintf(tempname, "_t%u", tempCounter);
    //printf("[DEBUG] newtemp: %s  currscope = %d\n", tempname,currscope());
    Symbol_t* sym = lookupSymbolInScope(tempname, currscope()); // Check at currentscope
    if (sym) {
        tempCounter++;
        return sym;
    }


    sym=insertSymbol(tempname, LOCAL_VAR, currscope(), yylineno); // Insertion at Symbol Table
    if (!sym) {
        fprintf(stderr, "[CRITICAL] insertSymbol failed for temp '%s' at scope %d\n", tempname, currscope());
        return NULL;
    }
    tempCounter++;
    return sym;
}

int currscopeoffset(void) { //As described at [PDF 9], Slide 50/54.
    switch (currscopespace()) {
        case programvar: return programVarOffset;
        case functionlocal: return functionLocalOffset;
        case formalarg: return formalArgOffset;
        default: assert(0);
    }
}

scopespace_t currscopespace(void) { //As described at [PDF 9], Slide 49/54.
    if (scopeSpaceCounter == 1)
        return programvar;
    if (scopeSpaceCounter % 2 == 0)
        return formalarg;
    return functionlocal;
}

    void incurrscopeoffset(void) { //As described at [PDF 9], Slide 50/54.
        switch (currscopespace()) {
            case programvar: ++programVarOffset; /*printf("[INCREMENT ProgramVar OFFSET] to %d at line %d \n",programVarOffset,yylineno);*/break;
            case functionlocal: ++functionLocalOffset;/*printf("[INCREMENT FunctionLocal OFFSET] to %d at line %d \n",functionLocalOffset,yylineno);*/ break;
            case formalarg: ++formalArgOffset;/*printf("[INCREMENT FormalArg OFFSET] to %d at line %d \n",formalArgOffset,yylineno);*/ break;
            default: assert(0);
        }
    }

void enterscopespace(void) {
    ++scopeSpaceCounter;
    //printf("[ENTER SCOPE FUNCTION] SC=%d  prog=%d  form=%d  local=%d\n",scopeSpaceCounter, programVarOffset,formalArgOffset, functionLocalOffset);


}

void exitscopespace(void) {
    if (scopeSpaceCounter <= 1) {
        fprintf(stderr, "[ERROR] Cannot exit global scopespace (counter = %d)\n", scopeSpaceCounter);
        exit(1);
    }
    --scopeSpaceCounter;
    //printf("[EXIT] SC=%d  prog=%d  form=%d  local=%d\n",scopeSpaceCounter, programVarOffset, formalArgOffset, functionLocalOffset);


}



void resetformalargsoffset(void) {//As described at [PDF 10], Slide 5/38. Function that resets formalArgOffset.
    formalArgOffset = 0;
}

void pushscopeoffset(int offset) {//As described at [PDF 10], Slide 5/38. Push at stack
    if (top >= SCOPE_STACK_SIZE - 1) {
        fprintf(stderr, "[ERROR] Scope offset stack overflow\n");
        exit(1);
    }
    //printf("[PUSHSCOPEOFFSET FUNCTION] Current offset is %d at line %d \n",offset,yylineno);
    scopeoffsetstack[++top] = offset;
}

int popscopeoffset(void) {//As described at [PDF 10], Slide 5/38. Pop from stack
    if (top < 0) {
        fprintf(stderr, "[ERROR] Scope offset stack underflow\n");
        exit(1);
    }
    return scopeoffsetstack[top--];
}

int nextquadlabel(void) { //As described at [PDF 10], Slide 5/38.
    return currQuad;
}

int nextquad(void) {
    return currQuad;
}


void restorecurrscopeoffset(int n) {//As described at [PDF 10], Slide 10/38.Restore previous scope offset
    switch (currscopespace()) {
        case programvar:        programVarOffset     = n; break;
        case functionlocal:     functionLocalOffset  = n; break;
        case formalarg:         formalArgOffset      = n; break;
        default:                assert(0);
    }
}



expr_t* lvalue_expr(Symbol_t* sym) {//As described at [PDF 10], Slide 18/38. Takes a symbol and returns an expr*
    assert(sym);

    expr_t* e = (expr_t*) malloc(sizeof(expr_t));
    memset(e, 0, sizeof(expr_t));

    e->next = NULL;
    e->sym  = sym;
    e->truelist = emptylist();;
    e->falselist = emptylist();;



    switch (sym->type) {
        case GLOBAL_VAR:
        case LOCAL_VAR:
        case FORMAL_ARG:
            e->type = var_e;
            break;
        case USER_FUNC:
            e->type = programfunc_e;
            break;
        case LIB_FUNC:
            e->type = libraryfunc_e;
            break;
        default:
            assert(0);  // Unknown symbol type
    }
    //printf("[DEBUG] lvalue_expr created expr: sym = %p, name = %s, type = %d, line = %d truelist = %d falselist = %d\n",
          //sym, sym ? sym->name : "NULL", sym ? sym->type : -1,sym->line,e->truelist,e->falselist);

    return e;
}

char* newtempfuncname(void) {//As described at [PDF 10], Slide 5/38. Returns new name for anonymous functions
    static int tempfunc_counter = 0;
    char* name = (char*) malloc(20);
    sprintf(name, "$%d", tempfunc_counter++);
    return name;
}

void patchlabel(int quadNo, int label) {//As described at [PDF 10], Slide 10/38. Update the value of unidentified quads
    //printf("[PATCH] patchlabel called with quadNo = %d, label = %d\n", quadNo+1, label+1);
    assert(quadNo < currQuad && quads[quadNo].label == -1);



    //printf("[PATCH DEBUG] Trying to patch quad[%u] with label %u using patchLabel.\n", quadNo+1, label+1);
    /*if (quads[quadNo].op == assign) {
        printf("[BUG] patchlist includes assign quad[%d]!\n", quadNo);
    }*/


    quads[quadNo].label = label;
}

void resetfunctionlocalsoffset(void) {//As described at [PDF 10], Slide 10/38.Resseting the global functionLocalOffset variable
    functionLocalOffset = 0;
}


expr_t* newexpr(expr_cat t) {

    expr_t* e = (expr_t*) malloc(sizeof(expr_t));
    memset(e, 0, sizeof(expr_t));       // Resetting all the fields
    e->type = t;
    e->truelist = emptylist();;
    e->falselist = emptylist();;
    e->sym = NULL;
    //printf("[DEBUG] newexpr function call at line %d for expression %s.\n",yylineno,expr_to_str(e));
    return e;
}


expr_t* newexpr_conststring(const char* s) {
    expr_t* e = newexpr(conststring_e);
    e->strConst = strdup(s);
    return e;
}


expr_t* newexpr_constnum(double n) {
    //printf("[DEBUG] newexpr_constnum function call at line %d\n",yylineno);
    expr_t* e = newexpr(constnum_e);
    e->numConst = n;
    return e;
}


expr_t* newexpr_constbool(int b) {
    expr_t* e = newexpr(constbool_e);
    e->boolConst = b;

    return e;
}


void emit_assign(expr_t* target, expr_t* value, int line) {
    emit(assign, target, value, NULL, -1, line);
}


expr_t* emit_iftableitem(expr_t* e, int line) {
    if (!e) return NULL;
    if (e->type != tableitem_e) {
        return e;
    }

    //printf("[DEBUG] emit_iftableitem(): emitting TABLEGETELEM for %s[%s]\n", e->sym ? e->sym->name : "NULL", (e->index && e->index->type == conststring_e) ? e->index->strConst : "non-string");


    /*if (e->type == tableitem_e) {
        printf("[DEBUG] emit_iftableitem(): emitting TABLEGETELEM for %s[%s]\n",
               e->sym->name,
               e->index && e->index->type == conststring_e ? e->index->strConst : "<?>");
    }*/
    expr_t* result = newexpr(var_e);
    result->sym = newtemp();

    emit(tablegetelem, result, lvalue_expr(e->sym), e->index, -1, line);
    return result;
}

expr_t* member_item(expr_t* lv, char* name) {
    //printf("[DEBUG] member_item function called at %d \n",yylineno);
    lv = emit_iftableitem(lv,yylineno);                          // Emit TABLEGETELEM if necessary
    expr_t* ti = newexpr(tableitem_e);                    // Creation of new tableitem
    ti->sym = lv->sym;                                  // The table
    ti->index = newexpr_conststring(name);              // The index

    //printf("[DEBUG] member_item(): base = %s, index = \"%s\"\n",lv->sym ? lv->sym->name : "NULL", name);

    return ti;
}

expr_t* make_call(expr_t* lv, expr_t* reversed_elist) { // As described at [PDF 10], Slide 27/38.

    expr_t* func = emit_iftableitem(lv, yylineno);
    if (!func) {
        printf("[ERROR] emit_iftableitem returned NULL\n");
        return NULL;
    }

    if (!func->sym) {
        func->sym = newtemp();
        //printf("[DEBUG] emit_iftableitem result had no sym — created: %s\n", func->sym->name);
    }

    expr_t* arg = reversed_elist;
    //static int call_counter = 0;
    //printf("[DEBUG] make_call #%d called at line %d\n", ++call_counter, yylineno);

    /*if (!lv) {
        printf("[ERROR] make_call called with NULL lv\n");
        return NULL;
    }*/


    while (arg) {
        //printf("[DEBUG] processing argument of type %d\n", arg->type);


        if (arg->type == boolexpr_e && !arg->sym) {
            arg->sym = newtemp();

            patchlist(arg->truelist, nextquad());
            emit(assign, lvalue_expr(arg->sym), newexpr_constbool(1), NULL, -1, yylineno);

            patchlist(arg->falselist, nextquad());
            emit(assign, lvalue_expr(arg->sym), newexpr_constbool(0), NULL, -1, yylineno);
        }


        if (arg->type == constnum_e || arg->type == conststring_e ||
            arg->type == constbool_e || arg->type == nil_e) {
            emit(param, NULL, arg, NULL, -1, yylineno);
        } else {

            if (!arg->sym) {
                arg->sym = newtemp();
                emit(assign, lvalue_expr(arg->sym), arg, NULL, -1, yylineno);
            }
            emit(param, NULL, lvalue_expr(arg->sym), NULL, -1, yylineno);
        }

        arg = arg->next;
    }


    emit(call, NULL, func, NULL, -1, yylineno);
    //printf("[DEBUG] emitted call to function\n");


    expr_t* result = newexpr(var_e);
    result->sym = newtemp();
    //printf("[DEBUG] getretval assigned to %s\n", result->sym->name);
    emit(getretval, result, NULL, NULL, -1, yylineno);

    return result;
}



expr_t* get_last(expr_t* list) { //As described at [PDF 10], Slide 28/38.
    if (!list) return NULL;
    while (list->next) list = list->next;
    return list;
}

const char* opcode_to_string(iopcode op) {
    switch (op) {
        case assign:        return "assign";
        case add:           return "add";
        case sub:           return "sub";
        case mul:           return "mul";
        case divide:        return "div";
        case mod:           return "mod";
        case uminus:        return "uminus";
        case and:           return "and";
        case or:            return "or";
        case not_:          return "not";
        case if_eq:         return "if_eq";
        case if_noteq:      return "if_noteq";
        case if_lesseq:     return "if_lesseq";
        case if_greatereq:  return "if_greatereq";
        case if_less:       return "if_less";
        case if_greater:    return "if_greater";
        case jump:          return "jump";
        case call:          return "call";
        case param:         return "param";
        case ret:           return "return";
        case getretval:     return "getretval";
        case funcstart:     return "funcstart";
        case funcend:       return "funcend";
        case tablecreate:   return "tablecreate";
        case tablegetelem:  return "tablegetelem";
        case tablesetelem:  return "tablesetelem";
        case nop:           return "nop";
        default:            return "UNKNOWN";
    }
}

const char* expr_to_str(expr_t* e) {
    if (!e) return "";

    switch (e->type) {
        case var_e:
        case tableitem_e:
        case programfunc_e:
        case libraryfunc_e:
        case assignexpr_e:
        case arithexpr_e:
        case boolexpr_e:
        case newtable_e:
        case conststring_e:
            return e->sym ? e->sym->name : "";

        case constbool_e:
            return e->boolConst ? "'true'" : "'false'";

        case nil_e:
            return "nil";

        case constnum_e:

            return "(constnum)";

        default:
            return "UNKNOWN_EXPR";
    }
}



void check_arith(expr_t* e, const char* context) {
    if (!e) return;

    switch (e->type) {
        case constnum_e:
        case arithexpr_e:
        case var_e:
        case assignexpr_e:
        case tableitem_e:
            return; // OK

        default:
            fprintf(stderr, "[ERROR] Illegal expression in %s (non-arithmetic type: %d)\n", context, e->type);
            exit(1);
    }
}



int istempname(char* s) {                       //As described at [PDF 10], Slide 37/38.
    return s && s[0] == '_';
}


int istempexpr(expr_t* e) {                   //As described at [PDF 10], Slide 37/38.
    return e && e->sym && istempname(e->sym->name);
}

void make_stmt (struct stmt_t* s) {//As described at [PDF 11], Slide 26/26.

        s->breaklist = emptylist();
        s->contlist  = emptylist();
        s->returnlist = emptylist();
    //printf("[DEBUG] make_stmt() called → breaklist=-1\n");
    }

IntList emptylist(void) {
    IntList list;
    list.size = 0;
    list.items = NULL;
    return list;
}

IntList newlist(int i) {

    if (quads[i].op != jump &&
        quads[i].op != if_eq &&
        quads[i].op != if_noteq &&
        quads[i].op != if_less &&
        quads[i].op != if_greater &&
        quads[i].op != if_lesseq &&
        quads[i].op != if_greatereq) {

        //printf("[DEBUG] newlist created from non-conditional quad[%d] (op=%d)\n", i + 1, quads[i].op);
        assert(0);
        }

    // Initialize list with one element
    IntList list;
    list.items = malloc(sizeof(int));
    list.items[0] = i;
    list.size = 1;

    // Set  label = -1 to mark it as unpatched
    quads[i].label = -1;
    //printf("[DEBUG] newlist(): returning quad[%d] as head of list (label set to -1)\n", i + 1);

    return list;
}

IntList mergelist(IntList a, IntList b) {
    IntList result;
    result.size = a.size + b.size;
    result.items = malloc(result.size * sizeof(int));

    for (int i = 0; i < a.size; ++i)
        result.items[i] = a.items[i];
    for (int i = 0; i < b.size; ++i)
        result.items[a.size + i] = b.items[i];

    //printf("[DEBUG] mergelist(): merged %d + %d items into new list of %d items\n", a.size, b.size, result.size);

    return result;
}


void patchlist(IntList list, int label) {
    for (int i = 0; i < list.size; ++i) {
        int q = list.items[i];


        if (quads[q].label != -1) {
            printf("[ERROR] patchlist(): quad[%d] already has label = %d (trying to patch to %d)\n", q + 1, quads[q].label+1, label+1);
            assert(0);
        }

        quads[q].label = label;
        //printf("[DEBUG] patchlist(): patched quad[%d] to label = %d\n", q + 1, label+1);
    }
}


void push_loopcounter(void) {
    Lc_stack_t* new_node = malloc(sizeof(Lc_stack_t));
    new_node->counter = 1;
    new_node->next = lcs_top;
    lcs_top = new_node;

    if (!lcs_bottom) {
        lcs_bottom = new_node;
    }
}

void pop_loopcounter(void) {
    if (!lcs_top) return;

    Lc_stack_t* temp = lcs_top;
    lcs_top = lcs_top->next;
    free(temp);

    if (!lcs_top)
        lcs_bottom = NULL;
}

int inLoop(void) {
    return lcs_top != NULL && lcs_top->counter > 0;
}




void printQuads() {
    printf("\n%-6s %-15s %-20s %-20s %-20s %-10s %-5s\n",
           "quad#", "opcode", "result", "arg1", "arg2", "label", "line");
    printf("-----------------------------------------------------------------------------------------------------------------------------\n");

    for (int i = 0; i < currQuad; ++i) {
        quad q = quads[i];

        char res[128], a1[128], a2[128];
        expr_to_buf(q.result, res, sizeof(res));
        expr_to_buf(q.arg1,   a1,  sizeof(a1));
        expr_to_buf(q.arg2,   a2,  sizeof(a2));

        printf("%-6d %-15s %-20s %-20s %-20s %-10d %-5d\n",
               i + 1,
               opcode_to_string(q.op),
               res,
               a1,
               a2,
               q.label + 1,
               q.line);
    }

    printf("-----------------------------------------------------------------------------------------------------------------------------\n\n");
}


void expr_to_buf(expr_t* e, char* out, size_t size) {
    if (!e) {
        snprintf(out, size, " ");
        return;
    }


    switch (e->type) {
        case constnum_e:
            snprintf(out, size, "%.5g", e->numConst);
            return;
        case constbool_e:
            snprintf(out, size, "%s", e->boolConst ? "'true'" : "'false'");
            return;
        case conststring_e:
            snprintf(out, size, "\"%s\"", e->strConst);
            return;
        case nil_e:
            snprintf(out, size, "nil");
            return;
        default:
            break;  // Πάμε να δούμε sym
    }

    if (e->sym && e->sym->name) {
        snprintf(out, size, "%s", e->sym->name);
    } else {
        snprintf(out, size, "--");
    }
}


void merge_jumps() {

    for (int i = 0; i < currQuad; ++i) {

        if (quads[i].op != jump) continue;
        if (quads[i].result != NULL || quads[i].arg1 != NULL || quads[i].arg2 != NULL) continue;
        if (i + 1 >= currQuad || quads[i + 1].op != funcstart) continue;


        int target = quads[i].label;
        while (target >= 0 && target < currQuad - 1 &&
               quads[target].op == jump &&
               quads[target].result == NULL &&
               quads[target].arg1   == NULL &&
               quads[target].arg2   == NULL &&
               quads[target + 1].op == funcstart) {
            target = quads[target].label;
        }
        quads[i].label = target;
    }
}



expr_t* make_bool_expr(expr_t* e, int patch_now) {
    //printf("[DEBUG] make_bool_expr() called with e = %p (patch_now = %d) at line %d\n", e, patch_now, yylineno);
    if (!e) return NULL;


    if (e->truelist.size == 0 && e->falselist.size == 0) {

        expr_t* result = newexpr(boolexpr_e);

        if (patch_now)
            result->sym = newtemp();


        int trueQuad = nextquad();
        //printf("[DEBUG] emitting if_eq at quad[%d] (op = %d)\n", trueQuad+1, if_eq);
        emit(if_eq, NULL, e, newexpr_constbool(1), -1, yylineno);


        int falseQuad = nextquad();
        //printf("[DEBUG] emitting jump at quad[%d] (op = %d)\n", falseQuad+1, jump);
        emit(jump, NULL, NULL, NULL, -1, yylineno);


        //printf("[DEBUG] About to create newlist truelist (%d)\n", trueQuad+1);
        result->truelist  = newlist(trueQuad);
        //printf("[DEBUG] About to create newlist falselist (%d)\n", falseQuad+1);
        result->falselist = newlist(falseQuad);


        if (patch_now) {
            patchlist(result->truelist, nextquad());
            emit(assign, result, newexpr_constbool(1), NULL, -1, yylineno);

            int skipFalse = nextquad();
            emit(jump, NULL, NULL, NULL, -1, yylineno);

            patchlist(result->falselist, nextquad());
            emit(assign, result, newexpr_constbool(0), NULL, -1, yylineno);

            patchlabel(skipFalse, nextquad());
        }
        return result;
    }


    if (e->truelist.size == 0 || e->falselist.size == 0) {

        if (!patch_now) return e;
        expr_t* result = newexpr(boolexpr_e);
        result->sym = newtemp();
        if (e->truelist.size > 0) {
            patchlist(e->truelist, nextquad());
            emit(assign, result, newexpr_constbool(1), NULL, -1, yylineno);
            int skipFalse = nextquad();
            emit(jump, NULL, NULL, NULL, -1, yylineno);
            if (e->falselist.size > 0) patchlist(e->falselist, nextquad());
            emit(assign, result, newexpr_constbool(0), NULL, -1, yylineno);
            patchlabel(skipFalse, nextquad());
        } else {
            if (e->falselist.size > 0) patchlist(e->falselist, nextquad());
            emit(assign, result, newexpr_constbool(0), NULL, -1, yylineno);
        }
        return result;
    }


    if (patch_now) {
        expr_t* result = newexpr(boolexpr_e);
        result->sym = newtemp();


        patchlist(e->truelist, nextquad());
        emit(assign, result, newexpr_constbool(1), NULL, -1, yylineno);


        int skipFalse = nextquad();
        emit(jump, NULL, NULL, NULL, -1, yylineno);


        patchlist(e->falselist, nextquad());
        emit(assign, result, newexpr_constbool(0), NULL, -1, yylineno);


        //printf("[DEBUG] About to patch skipFalse = %d (should point to jump), op = %d\n",skipFalse, quads[skipFalse].op);

        patchlabel(skipFalse, nextquad());

        return result;
    }


    return e;
}


int isIllegalAccess(Symbol_t *sym)
{
    if (!sym)                    return 0;
    if (sym->scope == 0)         return 0;
    if (sym->type == USER_FUNC || sym->type == LIB_FUNC)
        return 0;


    if (functionDepth == 0)      return 0;


    if (sym->funcDepth == functionDepth)
        return 0;


    return sym->funcDepth < functionDepth;
}


int isTempName(const char* name) {
    return name && name[0] == '_' && name[1] == 't';
}

expr_t* reverse_expr_list(expr_t* head) {
    expr_t* prev = NULL;
    expr_t* curr = head;
    while (curr) {
        expr_t* next = curr->next;
        curr->next = prev;
        prev = curr;
        curr = next;
    }
    return prev;
}

void verify_symbol_table(void) {

    printf("\n-- Verifying symbol table consistency --\n");

    for (int scope = 0; scope < MAX_SCOPE; ++scope) {
        Symbol_t* sym = scope_table[scope];

        while (sym) {
            const char* name = sym->name;


            if (sym->space == programvar && sym->scope != 0) {
                printf("[ERROR] Symbol '%s' marked as programvar but declared at scope %d\n", name, sym->scope);
            }

            if ((sym->space == formalarg || sym->space == functionlocal) && sym->scope == 0) {
                printf("[ERROR] Symbol '%s' marked as %s but declared at global scope\n",
                       name, sym->space == formalarg ? "formalarg" : "functionlocal");
            }


            if ((sym->space == formalarg || sym->space == functionlocal) && sym->scope > 0) {
                int parentScope = sym->scope - 1;
                int foundFunction = 0;

                Symbol_t* candidate = scope_table[parentScope];
                while (candidate) {
                    if (candidate->type == USER_FUNC || candidate->type == LIB_FUNC) {
                        foundFunction = 1;
                        break;
                    }
                    candidate = candidate->next;
                }

                if (!foundFunction) {
                    printf("[ERROR] Symbol '%s' marked as %s at scope %d but no function found in scope %d\n",
                           name,
                           sym->space == formalarg ? "formalarg" : "functionlocal",
                           sym->scope, parentScope);
                }
            }


            if (sym->type == USER_FUNC) {
                // 3.1 Έλεγχος iaddress και quads[]
                if (sym->iaddress < 0 || sym->iaddress >= currQuad) {
                    printf("[ERROR] Function '%s' has invalid iaddress %d (out of range)\n",
                           name, sym->iaddress);
                } else if (quads[sym->iaddress].op != funcstart) {
                    printf("[ERROR] Function '%s': quads[%d] is not funcstart (found opcode %d instead)\n",
                           name, sym->iaddress, quads[sym->iaddress].op);
                }


                int count = 0;
                FormalArg* arg = sym->formalList;
                while (arg) {
                    count++;
                    arg = arg->next;
                }

                if (count != sym->formal_count) {
                    printf("[ERROR] Function '%s' has formal_count = %d but actual list has %d arguments\n",
                           name, sym->formal_count, count);
                }


                int counted_locals = 0;
                int target_scope = sym->scope + 1;

                if (target_scope < MAX_SCOPE) {
                    Symbol_t* local = scope_table[target_scope];
                    while (local) {
                        if (local->space == functionlocal&& !istempname(local->name))
                            counted_locals++;
                        local = local->next;
                    }

                    if (counted_locals != sym->totallocals) {
                        printf("[ERROR] Function '%s': totallocals = %d, but found %d functionlocal symbols in scope %d\n",
                               name, sym->totallocals, counted_locals, target_scope);
                    }
                }
            }

            sym = sym->next;
        }
    }

    printf("-- Symbol table verification completed --\n");
}

