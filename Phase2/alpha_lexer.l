%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "alpha_lexer.h"
#include "Phase1Functions.h"

/* Lexer globals */
int   token_counter          = 0;
int   comment_depth          = 0;
int   start_blockcomment_line = 0;
int   nested_comment_detected = 0;
int   string_start_line      = 0;
char *decoded_string         = NULL;
int   decoded_index          = 0;
int   decoded_capacity       = 0;

#define YY_DECL int alpha_yylex(void *yylval)

static int emit(void *yylval, int line, const char *text,
                TokenCategory cat, TokenSubCat sub, int ret) {
    *((Token **)yylval) = createToken(line, ++token_counter, text, cat, sub);
    return ret;
}

#define EMIT(cat, sub, ret) return emit(yylval, yylineno, yytext, (cat), (sub), (ret))
#define EMIT_STR(cat, sub, content, ret) return emit(yylval, yylineno, (content), (cat), (sub), (ret))

%}

%x NESTED_BLOCK_COMMENT
%x STRING_STATE

%option yylineno
%option noyywrap
%option nounput

DIGIT   [0-9]
LETTER  [a-zA-Z]
ID      [a-zA-Z][a-zA-Z_0-9]*
REAL    [0-9]+\.[0-9]+

%%

"if"        { EMIT(KEYWORD, IF_,       IF_);       }
"else"      { EMIT(KEYWORD, ELSE_,     ELSE_);     }
"while"     { EMIT(KEYWORD, WHILE_,    WHILE_);    }
"for"       { EMIT(KEYWORD, FOR_,      FOR_);      }
"function"  { EMIT(KEYWORD, FUNCTION_, FUNCTION_); }
"return"    { EMIT(KEYWORD, RETURN_,   RETURN_);   }
"break"     { EMIT(KEYWORD, BREAK_,    BREAK_);    }
"continue"  { EMIT(KEYWORD, CONTINUE_, CONTINUE_); }
"and"       { EMIT(KEYWORD, AND_,      AND_);      }
"not"       { EMIT(KEYWORD, NOT_,      NOT_);      }
"or"        { EMIT(KEYWORD, OR_,       OR_);       }
"local"     { EMIT(KEYWORD, LOCAL_,    LOCAL_);    }
"true"      { EMIT(KEYWORD, TRUE_,     TRUE_);     }
"false"     { EMIT(KEYWORD, FALSE_,    FALSE_);    }
"nil"       { EMIT(KEYWORD, NIL_,      NIL_);      }

"=="  { EMIT(OPERATOR, EQUAL_,         EQUAL_);         }
"!="  { EMIT(OPERATOR, NOT_EQUAL_,     NOT_EQUAL_);     }
">="  { EMIT(OPERATOR, GREATER_EQUAL_, GREATER_EQUAL_); }
"<="  { EMIT(OPERATOR, LESS_EQUAL_,    LESS_EQUAL_);    }
"++"  { EMIT(OPERATOR, INCREMENT_,     INCREMENT_);     }
"--"  { EMIT(OPERATOR, DECREMENT_,     DECREMENT_);     }
"="   { EMIT(OPERATOR, ASSIGN_,        ASSIGN_);        }
"+"   { EMIT(OPERATOR, PLUS_,          PLUS_);          }
"-"   { EMIT(OPERATOR, MINUS_,         MINUS_);         }
"*"   { EMIT(OPERATOR, MULTIPLY_,      MULTIPLY_);      }
"/"   { EMIT(OPERATOR, DIVIDE_,        DIVIDE_);        }
"%"   { EMIT(OPERATOR, MODULUS_,       MODULUS_);       }
">"   { EMIT(OPERATOR, GREATER_THAN_,  GREATER_THAN_);  }
"<"   { EMIT(OPERATOR, LESS_THAN_,     LESS_THAN_);     }

"{"   { EMIT(PUNCTUATION, LEFT_BRACE_,             LEFT_BRACE_);             }
"}"   { EMIT(PUNCTUATION, RIGHT_BRACE_,            RIGHT_BRACE_);            }
"["   { EMIT(PUNCTUATION, LEFT_SQUARE_BRACKET_,    LEFT_SQUARE_BRACKET_);    }
"]"   { EMIT(PUNCTUATION, RIGHT_SQUARE_BRACKET_,   RIGHT_SQUARE_BRACKET_);   }
"("   { EMIT(PUNCTUATION, LEFT_PARENTHESIS_,       LEFT_PARENTHESIS_);       }
")"   { EMIT(PUNCTUATION, RIGHT_PARENTHESIS_,      RIGHT_PARENTHESIS_);      }
"::"  { EMIT(PUNCTUATION, DOUBLE_COLON_,           DOUBLE_COLON_);           }
":"   { EMIT(PUNCTUATION, COLON_,                  COLON_);                  }
".."  { EMIT(PUNCTUATION, DOUBLE_DOT_,             DOUBLE_DOT_);             }
"."   { EMIT(PUNCTUATION, DOT_,                    DOT_);                    }
";"   { EMIT(PUNCTUATION, SEMICOLON_,              SEMICOLON_);              }
","   { EMIT(PUNCTUATION, COMMA_,                  COMMA_);                  }

{REAL}    { EMIT(REALCONST, NOCHARACTERISTIC_, REALCONST); }
{DIGIT}+  { EMIT(INTCONST,  NOCHARACTERISTIC_, INTCONST);  }
{ID}      { EMIT(IDENT,     NOCHARACTERISTIC_, IDENT);      }

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
          Token *t = createToken(string_start_line, ++token_counter, decoded_string, STRING, NOCHARACTERISTIC_);
          free(decoded_string); decoded_string = NULL;
          *((Token **)yylval) = t;
          BEGIN(INITIAL); return STRING; }

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
              Token *t = createToken(string_start_line, ++token_counter, "", UNIDENTIFIED, NOCHARACTERISTIC_);
              *((Token **)yylval) = t;
              int c; while ((c = input()) != EOF && c != '"' && c != '\n') {}
              BEGIN(INITIAL); return NOCHARACTERISTIC_; }

    <<EOF>> { free(decoded_string); decoded_string = NULL;
              Token *t = createToken(string_start_line, ++token_counter, "", UNIDENTIFIED, NOCHARACTERISTIC_);
              *((Token **)yylval) = t; BEGIN(INITIAL); return NOCHARACTERISTIC_; }


    .|\n  { growStringBuffer(); decoded_string[decoded_index++] = yytext[0]; }
}

"//".*  {
    Token *t = createToken(yylineno, ++token_counter, "", COMMENTS, LINE_COMMENTS_);
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
                TokenSubCat sub = nested_comment_detected ? NESTED_COMMENTS_ : BLOCK_COMMENTS_;
                Token *t = createToken(start_blockcomment_line, ++token_counter, line_range, COMMENTS, sub);
                *((Token **)yylval) = t;
                start_blockcomment_line = 0;
                BEGIN(INITIAL); return COMMENTS;
              } }

    .|\n    { /* consume */ }

    <<EOF>> { Token *t = createToken(start_blockcomment_line, ++token_counter, "", UNIDENTIFIED, NOCHARACTERISTIC_);
              *((Token **)yylval) = t;
              comment_depth = 0; start_blockcomment_line = 0;
              BEGIN(INITIAL); return NOCHARACTERISTIC_; }
}

[ \t\n\r\f\v]+  { /* ignore */ }

<INITIAL><<EOF>>  { return -1; }

.   { EMIT(UNIDENTIFIED, NOCHARACTERISTIC_, NOCHARACTERISTIC_); }

%%
