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

/* Token SubCategory */
typedef enum {
    /* Keywords */
    IF, ELSE, WHILE, FOR, FUNCTION, RETURN, BREAK, CONTINUE,
    AND, NOT, OR, LOCAL, TRUE, FALSE, NIL,
    /* Operators */
    ASSIGN, PLUS, MINUS, MULTIPLY, DIVIDE, MODULUS,
    EQUAL, NOT_EQUAL, INCREMENT, DECREMENT,
    GREATER_THAN, LESS_THAN, GREATER_EQUAL, LESS_EQUAL,
    /* Punctuation */
    LEFT_BRACE, RIGHT_BRACE,
    LEFT_SQUARE_BRACKET, RIGHT_SQUARE_BRACKET,
    LEFT_PARENTHESIS, RIGHT_PARENTHESIS,
    SEMICOLON, COMMA, COLON, DOUBLE_COLON, DOT, DOUBLE_DOT,
    /* Comments */
    LINE_COMMENTS, BLOCK_COMMENTS, NESTED_COMMENTS,
    /* Fallback */
    NOCHARACTERISTIC
} TokenSubCat;

/* Token struct */
typedef struct alpha_token_t {
    int         lineNumber;
    int         tokenNumber;
    char       *tokenContent;
    TokenCategory  tokenCategory;
    TokenSubCat   tokenCharacteristic;
    struct alpha_token_t *next;
} Token;

typedef Token *TokenList;

extern TokenList lexList;

/* Declaration of variables and functions that i am using*/
int         alpha_yylex(void *yylval);

Token      *createToken(int line, int number, const char *content,TokenCategory cat, TokenSubCat sub);

int         listAppend(TokenList *list, Token *token);
void        printTokens(TokenList head, FILE *out);
void        checkForLexicalErrors(TokenList list);
void        destroyTokenList(Token **head);

const char *categoryToString(TokenCategory cat);
const char *subtypeToString(TokenSubCat sub);

void        growStringBuffer(void);   /* used internally by lexer */

#endif /* PROJECTPHASE1_ALPHA_LEXER_H */