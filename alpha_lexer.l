%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "alpha_lexer.h"
#include "Phase1Functions.h"

/*  Lexer globals  */
int   token_counter          = 0;
int   comment_depth          = 0;
int   start_blockcomment_line = 0;
int   nested_comment_detected = 0;
int   string_start_line      = 0;
char *decoded_string         = NULL;
int   decoded_index          = 0;
int   decoded_capacity       = 0;

/* Override the generated function name */
#define YY_DECL int alpha_yylex(void *yylval)

/* Helper fuction that is used multiply times in code*/
static int emit(void *yylval, int line, const char *text,
                TokenCategory cat, TokenSubCat sub, int ret) {
    *((Token **)yylval) = createToken(line, ++token_counter, text, cat, sub);
    return ret;
}


#define EMIT(cat, sub, ret) return emit(yylval, yylineno, yytext, (cat), (sub), (ret))


#define EMIT_STR(cat, sub, content, ret) return emit(yylval, yylineno, (content), (cat), (sub), (ret))

%}

/* Exclusive start conditions */
%x NESTED_BLOCK_COMMENT
%x STRING_STATE

%option yylineno
%option noyywrap
%option nounput

/*  Named patterns  */
DIGIT   [0-9]
LETTER  [a-zA-Z]
ID      [a-zA-Z][a-zA-Z_0-9]*
REAL    [0-9]+\.[0-9]+

%%


"if"        { EMIT(KEYWORD, IF,       IF);       }
"else"      { EMIT(KEYWORD, ELSE,     ELSE);     }
"while"     { EMIT(KEYWORD, WHILE,    WHILE);    }
"for"       { EMIT(KEYWORD, FOR,      FOR);      }
"function"  { EMIT(KEYWORD, FUNCTION, FUNCTION); }
"return"    { EMIT(KEYWORD, RETURN,   RETURN);   }
"break"     { EMIT(KEYWORD, BREAK,    BREAK);    }
"continue"  { EMIT(KEYWORD, CONTINUE, CONTINUE); }
"and"       { EMIT(KEYWORD, AND,      AND);      }
"not"       { EMIT(KEYWORD, NOT,      NOT);      }
"or"        { EMIT(KEYWORD, OR,       OR);       }
"local"     { EMIT(KEYWORD, LOCAL,    LOCAL);    }
"true"      { EMIT(KEYWORD, TRUE,     TRUE);     }
"false"     { EMIT(KEYWORD, FALSE,    FALSE);    }
"nil"       { EMIT(KEYWORD, NIL,      NIL);      }


"=="  { EMIT(OPERATOR, EQUAL,         EQUAL);         }
"!="  { EMIT(OPERATOR, NOT_EQUAL,     NOT_EQUAL);     }
">="  { EMIT(OPERATOR, GREATER_EQUAL, GREATER_EQUAL); }
"<="  { EMIT(OPERATOR, LESS_EQUAL,    LESS_EQUAL);    }
"++"  { EMIT(OPERATOR, INCREMENT,     INCREMENT);     }
"--"  { EMIT(OPERATOR, DECREMENT,     DECREMENT);     }
"="   { EMIT(OPERATOR, ASSIGN,        ASSIGN);        }
"+"   { EMIT(OPERATOR, PLUS,          PLUS);          }
"-"   { EMIT(OPERATOR, MINUS,         MINUS);         }
"*"   { EMIT(OPERATOR, MULTIPLY,      MULTIPLY);      }
"/"   { EMIT(OPERATOR, DIVIDE,        DIVIDE);        }
"%"   { EMIT(OPERATOR, MODULUS,       MODULUS);       }
">"   { EMIT(OPERATOR, GREATER_THAN,  GREATER_THAN);  }
"<"   { EMIT(OPERATOR, LESS_THAN,     LESS_THAN);     }


"{"   { EMIT(PUNCTUATION, LEFT_BRACE,             LEFT_BRACE);             }
"}"   { EMIT(PUNCTUATION, RIGHT_BRACE,            RIGHT_BRACE);            }
"["   { EMIT(PUNCTUATION, LEFT_SQUARE_BRACKET,    LEFT_SQUARE_BRACKET);    }
"]"   { EMIT(PUNCTUATION, RIGHT_SQUARE_BRACKET,   RIGHT_SQUARE_BRACKET);   }
"("   { EMIT(PUNCTUATION, LEFT_PARENTHESIS,       LEFT_PARENTHESIS);       }
")"   { EMIT(PUNCTUATION, RIGHT_PARENTHESIS,      RIGHT_PARENTHESIS);      }
"::"  { EMIT(PUNCTUATION, DOUBLE_COLON,           DOUBLE_COLON);           }
":"   { EMIT(PUNCTUATION, COLON,                  COLON);                  }
".."  { EMIT(PUNCTUATION, DOUBLE_DOT,             DOUBLE_DOT);             }
"."   { EMIT(PUNCTUATION, DOT,                    DOT);                    }
";"   { EMIT(PUNCTUATION, SEMICOLON,              SEMICOLON);              }
","   { EMIT(PUNCTUATION, COMMA,                  COMMA);                  }


{REAL}    { EMIT(REALCONST, NOCHARACTERISTIC, REALCONST); }
{DIGIT}+  { EMIT(INTCONST,  NOCHARACTERISTIC, INTCONST);  }
{ID}      { EMIT(IDENT,     NOCHARACTERISTIC, IDENT);     }


\" {
    string_start_line = yylineno;
    decoded_string    = malloc(INITIAL_STR_CAP);
    if (!decoded_string) { perror("malloc"); exit(EXIT_FAILURE); }
    decoded_index    = 0;
    decoded_capacity = INITIAL_STR_CAP;
    BEGIN(STRING_STATE);
}

<STRING_STATE>{
    \"  { decoded_string[decoded_index] = '\0';
          Token *t = createToken(string_start_line, ++token_counter, decoded_string, STRING, NOCHARACTERISTIC);
          free(decoded_string); decoded_string = NULL;
          *((Token **)yylval) = t;
          BEGIN(INITIAL); return STRING; }

    /* Recognised escape sequences */
    \\n   { growStringBuffer(); decoded_string[decoded_index++] = '\n'; }
    \\t   { growStringBuffer(); decoded_string[decoded_index++] = '\t'; }
    \\\"  { growStringBuffer(); decoded_string[decoded_index++] = '"';  }
    \\\\  { growStringBuffer(); decoded_string[decoded_index++] = '\\'; }
    \\r   { growStringBuffer(); decoded_string[decoded_index++] = '\r'; }
    \\b   { growStringBuffer(); decoded_string[decoded_index++] = '\b'; }
    \\f   { growStringBuffer(); decoded_string[decoded_index++] = '\f'; }
    \\v   { growStringBuffer(); decoded_string[decoded_index++] = '\v'; }
    \\a   { growStringBuffer(); decoded_string[decoded_index++] = '\a'; }
    \\0   { growStringBuffer(); decoded_string[decoded_index++] = '\0'; }

    \\[^\n] { free(decoded_string); decoded_string = NULL;
                   Token *t = createToken(string_start_line, ++token_counter, "", UNIDENTIFIED, NOCHARACTERISTIC);
                   *((Token **)yylval) = t;
                   int c; while ((c = input()) != EOF && c != '"' && c != '\n') {}
                   BEGIN(INITIAL); return NOCHARACTERISTIC; }

    <<EOF>> { free(decoded_string); decoded_string = NULL;
                  Token *t = createToken(string_start_line, ++token_counter, "", UNIDENTIFIED, NOCHARACTERISTIC);
                  *((Token **)yylval) = t; BEGIN(INITIAL); return NOCHARACTERISTIC; }



    /* Any other character */
    .|\n  { growStringBuffer(); decoded_string[decoded_index++] = yytext[0]; }
}


"//".*  {
    Token *t = createToken(yylineno, ++token_counter, "", COMMENTS, LINE_COMMENTS);
    *((Token **)yylval) = t;
    return COMMENTS;
}


"/*" {
    start_blockcomment_line  = yylineno;
    comment_depth            = 1;
    nested_comment_detected  = 0;
    BEGIN(NESTED_BLOCK_COMMENT);
}

<NESTED_BLOCK_COMMENT>{
    "/*"    { comment_depth++; nested_comment_detected = 1; }

    "*/"    { comment_depth--;
              if (comment_depth == 0) {
                char line_range[COMMENT_LINE_BUF];
                snprintf(line_range, sizeof(line_range), "%d - %d", start_blockcomment_line, yylineno);
                TokenSubCat sub = nested_comment_detected ? NESTED_COMMENTS : BLOCK_COMMENTS;
                Token *t = createToken(start_blockcomment_line, ++token_counter, line_range, COMMENTS, sub);
                *((Token **)yylval) = t;
                start_blockcomment_line = 0;
                BEGIN(INITIAL); return COMMENTS;
              } }

    .|\n    { /* consume */ }

    <<EOF>> { Token *t = createToken(start_blockcomment_line, ++token_counter, "", UNIDENTIFIED, NOCHARACTERISTIC);
              *((Token **)yylval) = t;
              comment_depth = 0; start_blockcomment_line = 0;
              BEGIN(INITIAL); return NOCHARACTERISTIC; }
}


[ \t\n\r\f\v]+  { /* ignore */ }


<INITIAL><<EOF>>  { return -1; }


.   { EMIT(UNIDENTIFIED, NOCHARACTERISTIC, NOCHARACTERISTIC); }

%%
