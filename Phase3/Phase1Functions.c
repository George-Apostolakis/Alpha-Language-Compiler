#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#include "alpha_lexer.h"
#include "Phase1Functions.h"


int  syntax_errors = 0;


extern char *decoded_string;
extern int   decoded_index;
extern int   decoded_capacity;
extern FILE *output_file;



/* Adds a token to the end of the list. Returns 1 on success, 0 on NULL. */
int listAppend(TokenList *list, Token *token) {
    if (!token) return 0;

    token->next = NULL;

    if (*list == NULL) {
        *list = token;
        return 1;
    }

    Token *cur = *list;
    while (cur->next)
        cur = cur->next;
    cur->next = token;
    return 1;
}

/* Free every node in the list and set the head pointer to NULL. */
void destroyTokenList(Token **head) {
    Token *cur = *head;
    while (cur) {
        Token *next = cur->next;
        free(cur->tokenContent);
        free(cur);
        cur = next;
    }
    *head = NULL;
}

/* Function that creates tokens*/

Token *createToken(int line, int number, const char *content,TokenCategory cat, TokenSubCat sub) {

    Token *t = malloc(sizeof(Token));
    if (!t) {
        perror("createToken: malloc failed");
        exit(EXIT_FAILURE);
    }
    t->lineNumber          = line;
    t->tokenNumber         = number;
    t->tokenContent        = strdup(content);
    t->tokenCategory       = cat;
    t->tokenCharacteristic = sub;
    t->next                = NULL;
    return t;
}




static const char *typeHint(TokenCategory cat) {
    switch (cat) {
        case INTCONST:
        case REALCONST:  return "<--int";
        case IDENT:
        case STRING:     return "<--char*";
        default:         return "<--enumerated";
    }
}


/* Printing Function */
void printTokens(TokenList head, FILE *out) {
    fprintf(out, "%-8s %-10s %-35s %-20s %-25s %-15s\n",
            "Line", "Token#", "TokenContent", "Category", "Characteristic", "TypeHint");
    fprintf(out, "%s\n",
            "-----------------------------------------------------------"
            "----------------------------------------------------------------");

    for (Token *cur = head; cur; cur = cur->next) {

        fprintf(out, "%-8d #%-9d \"%-33s\"",
                cur->lineNumber, cur->tokenNumber, cur->tokenContent);

        if (cur->tokenCategory == UNIDENTIFIED) {
            fprintf(out, "  This token is UNIDENTIFIED.\n");
            continue;
        }

        if (cur->tokenCharacteristic == NOCHARACTERISTIC_) {
            /* INTCONST / REALCONST / IDENT / STRING */
            if (cur->tokenCategory == IDENT || cur->tokenCategory == STRING) {
                fprintf(out, "  %-18s \"%-24s\" %s\n",
                        categoryToString(cur->tokenCategory),
                        cur->tokenContent,
                        typeHint(cur->tokenCategory));
            } else {
                fprintf(out, "  %-18s %-25s %s\n",
                        categoryToString(cur->tokenCategory),
                        cur->tokenContent,
                        typeHint(cur->tokenCategory));
            }
        } else {
            /* KEYWORD / OPERATOR / PUNCTUATION / COMMENTS */
            fprintf(out, "  %-18s %-25s %s\n",
                    categoryToString(cur->tokenCategory),
                    subtypeToString(cur->tokenCharacteristic),
                    typeHint(cur->tokenCategory));
        }
    }
}

/* Checks for Lexicographical Errors */

void checkForLexicalErrors(TokenList list) {
    if (!list) {
        fprintf(output_file, "Empty token list\n");
        exit(EXIT_FAILURE);
    }

    bool found = false;
    for (Token *cur = list; cur; cur = cur->next) {
        if (cur->tokenCategory == UNIDENTIFIED) {
            fprintf(output_file,
                    "[LEXICAL ERROR] Undefined token '%s' at line %d\n",
                    cur->tokenContent, cur->lineNumber);
            syntax_errors++;
            found = true;
        }
    }

    if (found) {
        fprintf(output_file,
                "[LEXICAL ERROR] Lexical analysis found %d error(s). "
                "Compiling aborted.\n", syntax_errors);
        exit(EXIT_FAILURE);
    }
}

/* Converts Enum to Strings for printing */

const char *categoryToString(TokenCategory cat) {
    static const char *names[] = {
        "KEYWORD", "INTCONST", "REALCONST", "IDENT", "STRING",
        "OPERATOR", "COMMENTS", "PUNCTUATION", "UNIDENTIFIED"
    };
    if (cat <= UNIDENTIFIED)
        return names[cat];
    return "UNKNOWN_CATEGORY";
}

const char *subtypeToString(TokenSubCat sub) {
    static const char *names[] = {
        "IF","ELSE","WHILE","FOR","FUNCTION","RETURN","BREAK","CONTINUE",
        "AND","NOT","OR","LOCAL","TRUE","FALSE","NIL",
        "ASSIGN","PLUS","MINUS","MULTIPLY","DIVIDE","MODULUS",
        "EQUAL","NOT_EQUAL","INCREMENT","DECREMENT",
        "GREATER_THAN","LESS_THAN","GREATER_EQUAL","LESS_EQUAL",
        "LEFT_BRACE","RIGHT_BRACE",
        "LEFT_SQUARE_BRACKET","RIGHT_SQUARE_BRACKET",
        "LEFT_PARENTHESIS","RIGHT_PARENTHESIS",
        "SEMICOLON","COMMA","COLON","DOUBLE_COLON","DOT","DOUBLE_DOT",
        "LINE_COMMENTS","BLOCK_COMMENTS","NESTED_COMMENTS",
        "NOCHARACTERISTIC"
    };
    if (sub <= NOCHARACTERISTIC_)
        return names[sub];
    return "UNKNOWN_SUBTYPE";
}

/* In case of LARGE strings, reallocates the string buffer*/

void growStringBuffer(void) {
    if (decoded_index >= decoded_capacity - 1) {
        decoded_capacity *= 2;
        char *tmp = realloc(decoded_string, decoded_capacity);
        if (!tmp) {
            perror("growStringBuffer: realloc failed");
            free(decoded_string);
            exit(EXIT_FAILURE);
        }
        decoded_string = tmp;
    }
}