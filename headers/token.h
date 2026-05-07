#pragma once

/* MAIN TOKEN CATEGORIES */
typedef enum{
    KEYWORD,
    IDENTIFIER,
    INTCONST,
    REALCONST,
    STRING,
    OPERATOR,
    PUNCTUATION,
    COMMENT,
    UNIDENTIFIED
}TokenCategory;

/* SECONDARY TOKEN CATEGORIES */
typedef enum{
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
    LINE_COMMENT, BLOCK_COMMENT, NESTED_COMMENT,
    /* Fallback */
    NO_SUB_CATEGORY
}TokenSubCategory;

/**
 * Takes a Token Category and returns it as a string instead of unsigned int (enums value).
 * @param[in] cat The enum of the Tokens Category.
 * @return String of the enum.
 */
const char *CategoryToString(TokenCategory cat);

/**
 * Takes a Token Subcategory and returns it as a string instead of unsigned int (enums value).
 * @param[in] cat The enum of the Tokens Subcategory.
 * @return String of the enum.
 */
const char *SubCategoryToString(TokenSubCategory cat);

/**
 * Takes a Tokens Value and hints its type.
 * @param[in] cat The tokens->mainCategory .
 * @return String of the type.
 */
const char *typeHint(TokenCategory cat);

typedef struct alpha_lang_token{
    int lineNumber;
    int tokenNumber;
    char *lexeme;
    TokenCategory mainCat;
    TokenSubCategory secondaryCat;

    // Next Token for the Linked List
    struct alpha_lang_token *next;
}Token;