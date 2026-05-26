#ifndef PROJECTPHASE1_ALPHA_LEXER_H
#define PROJECTPHASE1_ALPHA_LEXER_H

#include <stdio.h>

#define BUFFER_SIZE        8192
#define INITIAL_STR_CAP    1024
#define COMMENT_LINE_BUF   50

/* Tokens Category */
typedef enum {
    KEYWORD,
    INTCONST,
    REALCONST,
    IDENT,
    STRING,
    OPERATOR,
    COMMENTS,
    PUNCTUATION,
    UNIDENTIFIED
} TokenCategory;

/* Token SubCategory — suffixed with _ to avoid clash with Bison token names */
typedef enum {
    /* Keywords */
    IF_, ELSE_, WHILE_, FOR_, FUNCTION_, RETURN_, BREAK_, CONTINUE_,
    AND_, NOT_, OR_, LOCAL_, TRUE_, FALSE_, NIL_,
    /* Operators */
    ASSIGN_, PLUS_, MINUS_, MULTIPLY_, DIVIDE_, MODULUS_,
    EQUAL_, NOT_EQUAL_, INCREMENT_, DECREMENT_,
    GREATER_THAN_, LESS_THAN_, GREATER_EQUAL_, LESS_EQUAL_,
    /* Punctuation */
    LEFT_BRACE_, RIGHT_BRACE_,
    LEFT_SQUARE_BRACKET_, RIGHT_SQUARE_BRACKET_,
    LEFT_PARENTHESIS_, RIGHT_PARENTHESIS_,
    SEMICOLON_, COMMA_, COLON_, DOUBLE_COLON_, DOT_, DOUBLE_DOT_,
    /* Comments */
    LINE_COMMENTS_, BLOCK_COMMENTS_, NESTED_COMMENTS_,
    /* Fallback */
    NOCHARACTERISTIC_
} TokenSubCat;

/* Token struct */
typedef struct alpha_token_t {
    int           lineNumber;
    int           tokenNumber;
    char         *tokenContent;
    TokenCategory tokenCategory;
    TokenSubCat   tokenCharacteristic;
    struct alpha_token_t *next;
} Token;

typedef Token *TokenList;

extern TokenList lexList;

/* Declaration of variables and functions */
int         alpha_yylex(void *yylval);
void yyrestart(FILE *input_file);

Token      *createToken(int line, int number, const char *content,
                        TokenCategory cat, TokenSubCat sub);

int         listAppend(TokenList *list, Token *token);
void        printTokens(TokenList head, FILE *out);
void        checkForLexicalErrors(TokenList list);
void        destroyTokenList(Token **head);

const char *categoryToString(TokenCategory cat);
const char *subtypeToString(TokenSubCat sub);

void        growStringBuffer(void);


#endif /* PROJECTPHASE1_ALPHA_LEXER_H */