#include "../headers/token.h"

const char *CategoryToString(TokenCategory cat)
{
    static const char *main_categories_strings[] = {
        "KEYWORD",
        "IDENTIFIER",
        "INTCONST",
        "REALCONST",
        "STRING",
        "OPERATOR",
        "PUNCTUATION",
        "COMMENT",
        "UNIDENTIFIED"};

    return main_categories_strings[cat];
}

const char *SubCategoryToString(TokenSubCategory cat)
{
    static const char *sec_categories_strings[] = {
        "IF", "ELSE", "WHILE", "FOR", "FUNCTION", "RETURN", "BREAK", "CONTINUE",
        "AND", "NOT", "OR", "LOCAL", "TRUE", "FALSE", "NIL",
        "ASSIGN", "PLUS", "MINUS", "MULTIPLY", "DIVIDE", "MODULUS",
        "EQUAL", "NOT_EQUAL", "INCREMENT", "DECREMENT",
        "GREATER_THAN", "LESS_THAN", "GREATER_EQUAL", "LESS_EQUAL",
        "LEFT_BRACE", "RIGHT_BRACE",
        "LEFT_SQUARE_BRACKET", "RIGHT_SQUARE_BRACKET",
        "LEFT_PARENTHESIS", "RIGHT_PARENTHESIS",
        "SEMICOLON", "COMMA", "COLON", "DOUBLE_COLON", "DOT", "DOUBLE_DOT",
        "LINE_COMMENTS", "BLOCK_COMMENTS", "NESTED_COMMENTS",
        "NO_SUB_CATEGORY"};

    return sec_categories_strings[cat];
}

const char *typeHint(TokenCategory cat)
{
    switch (cat)
    {
    case STRING_:
    case IDENTIFIER_:
        return "char*";
    case INTCONST_:
        return "int";
    case REALCONST_:
        return "float";
    default:
        return "enumerator";
    }
}