#include "../headers/linked_list.h"
#include <stdlib.h> // for NUll
#include <stdio.h>  // for printf propably

struct List
{
    int size;
    Token *head;
    Token *tail;
};

int  syntax_errors = 0;
extern FILE* output_file;

int LinkedList_CreateEmpty(List **list)
{
    if (!list)
    {
        fprintf(stderr, "LinkedList_CreateEmpty: ERROR double pointer is NULL\n");
        return LINKEDLIST_NULL;
    }

    *list = (List *)malloc(sizeof(List));
    if (!(*list))
    {
        fprintf(stderr, "LinkedList_CreateEmpty: Memory allocation failed\n");
        return LINKEDLIST_ALLOCATION_FAILED;
    }

    (*list)->head = NULL;
    (*list)->tail = NULL;
    (*list)->size = 0;
    return 1;
}

int LinkedList_AddToEnd(List **list, Token value)
{
    Token *newNode;
    if (!list)
    {
        fprintf(stderr, "LinkedList_AddToEnd: ERROR double pointer is NULL\n");
        return LINKEDLIST_NULL;
    }

    if (!(*list))
    {
        fprintf(stderr, "LinkedList_AddToEnd: ERROR list pointer is NULL\n");
        return LINKEDLIST_NULL;
    }

    newNode = (Token *)malloc(sizeof(Token));
    if (!newNode)
    {
        fprintf(stderr, "LinkedList_AddToEnd: Memory allocation failed\n");
        return LINKEDLIST_ALLOCATION_FAILED;
    }
    newNode->lineNumber = value.lineNumber;
    newNode->tokenNumber = value.tokenNumber;
    newNode->lexeme = value.lexeme;
    newNode->mainCat = value.mainCat;
    newNode->secondaryCat = value.secondaryCat;
    newNode->next = NULL;

    if ((*list)->tail == NULL)
    {
        (*list)->head = newNode;
        (*list)->tail = newNode;
    }
    else
    {
        (*list)->tail->next = newNode;
        (*list)->tail = newNode;
    }
    (*list)->size++;
    return 1;
}

int LinkedList_GetLength(const List *list)
{
    if (!list)
        return LINKEDLIST_NULL;

    return list->size;
}

void LinkedList_Free(List **list)
{
    Token *tmp, *toBeFreed;

    // CASE1: NULL LIST
    if (!list)
        return;

    if (!(*list))
        return;
        
    // CASE3: NORMAL CASE
    tmp = (*list)->head;
    while (tmp != NULL)
    {
        toBeFreed = tmp;
        tmp = tmp->next;

        if (toBeFreed->lexeme)
            free(toBeFreed->lexeme);
        free(toBeFreed);
    }
    // Reset the list to empty state
    free(*list);
    *list = NULL;
}

void LinkedList_Print(const List *list, FILE *out)
{
    fprintf(out, "%-8s %-10s %-35s %-20s %-25s %-15s\n",
            "Line", "Token#", "TokenContent", "Category", "Value", "TypeHint");
    fprintf(out, "%s\n",
            "-----------------------------------------------------------"
            "----------------------------------------------------------------");

    for (Token *cur = list->head; cur; cur = cur->next)
    {

        fprintf(out, "%-8d #%-9d \"%-33s\"",
                cur->lineNumber, cur->tokenNumber, cur->lexeme);

        if (cur->mainCat == UNIDENTIFIED)
        {
            fprintf(out, "  %-18s %-25s\n", "UNIDENTIFIED", "NO_SUB_CATEGORY");
            continue;
        }
        if (cur->secondaryCat == NO_SUB_CATEGORY)
        {
            /* INTCONST / REALCONST / IDENT / STRING */
            if (cur->mainCat == IDENTIFIER || cur->mainCat == STRING)
            {
                fprintf(out, "  %-18s \"%-23s\" <--%s\n",
                        CategoryToString(cur->mainCat),
                        cur->lexeme,
                        typeHint(cur->mainCat));
            }
            else
            {
                fprintf(out, "  %-18s %-25s <--%s\n",
                        CategoryToString(cur->mainCat),
                        cur->lexeme,
                        typeHint(cur->mainCat));
            }
        }
        else
        {
            /* KEYWORD / OPERATOR / PUNCTUATION / COMMENTS */
            fprintf(out, "  %-18s %-25s <--%s\n",
                    CategoryToString(cur->mainCat),
                    SubCategoryToString(cur->secondaryCat),
                    typeHint(cur->mainCat));
        }
    }
}

int LinkedList_CheckErrors(const List *list){
    if (!list) {
        fprintf(output_file, "NULL token list\n");
        return LINKEDLIST_NULL;
    }

    bool found = false;
    for (Token *cur = list->head; cur; cur = cur->next) {
        if (cur->mainCat == UNIDENTIFIED) {
            fprintf(output_file,
                    "[LEXICAL ERROR] Undefined token '%s' at line %d\n",
                    cur->lexeme, cur->lineNumber);
            syntax_errors++;
            found = true;
        }
    }

    if (found) {
        fprintf(output_file,
                "[LEXICAL ERROR] Lexical analysis found %d error(s). "
                "Compiling aborted.\n", syntax_errors);
        return LINKEDLIST_UNIDENTIFIED_TOKENS;
    }

    return 1;
}