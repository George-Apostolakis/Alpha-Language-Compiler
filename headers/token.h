#pragma once

/* MAIN TOKEN CATEGORIES */
typedef enum{
    KEYWORD_,
    IDENTIFIER_,
    INTCONST_,
    REALCONST_,
    STRING_,
    OPERATOR_,
    PUNCTUATION_,
    COMMENT_,
    UNIDENTIFIED_
}TokenCategory;

/* SECONDARY TOKEN CATEGORIES */
typedef enum{
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
    LINE_COMMENT_, BLOCK_COMMENT_, NESTED_COMMENT_,
    /* Fallback */
    NO_SUB_CATEGORY_
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