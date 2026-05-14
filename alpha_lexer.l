%{
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include "headers/token.h"
    #include <stdbool.h>

    #define INITIAL_STRING_CAP  1024
    #define YY_DECL int alpha_yylex(void *yylval)

    int tokenNumber = 0;

    // String Intented Variables
    int     string_starting_line = 0;
    int     string_index         = 0;
    int     string_cap           = 0;
    char*   string_ptr           = NULL;

    // Block Comment Variables
    int     block_comment_depth         = 0;
    int     block_comment_starting_line = 0;
    bool    block_comment_is_nested     = false;

    void growStringBuffer(void) {
        if (string_index >= string_cap - 1) {
            string_cap *= 2;
            char *tmp = realloc(string_ptr, string_cap);
            if (!tmp) {
                perror("growStringBuffer: realloc failed");
                free(string_ptr);
                exit(-1);
            }
            string_ptr = tmp;
        }
    }
    
    static int emit(void *yylval, int lineNumber , char* lexeme ,
                    TokenCategory mainCat, TokenSubCategory secondaryCat,int ret){
        Token* argToken = (Token*)yylval;
        if(!argToken){       
            printf("[DEBUG] FINISHED Investigating %d Token\n",tokenNumber);
            return ret;
        }
        
        tokenNumber++;

        argToken->lineNumber = lineNumber;
        argToken->tokenNumber = tokenNumber;
        argToken->lexeme = strdup(lexeme?lexeme:"");
        argToken->mainCat = mainCat;
        argToken->secondaryCat = secondaryCat;

        return ret;
    }

    #define EMIT(token, sub , ret) return emit(yylval,yylineno ,yytext , (token), (sub),(ret))
%}

%option noyywrap
%option yylineno
%option nounput

%x STRING_STATE
%x NESTED_COMMENT_STATE

DIGIT   [0-9]
LETTER  [a-zA-Z]
ID      [a-zA-Z][a-zA-Z_0-9]*
REAL    [0-9]+\.[0-9]+

%%

"if"        { EMIT(KEYWORD_, IF_,       IF_);       }
"else"      { EMIT(KEYWORD_, ELSE_,     ELSE_);     }
"while"     { EMIT(KEYWORD_, WHILE_,    WHILE_);    }
"for"       { EMIT(KEYWORD_, FOR_,      FOR_);      }
"function"  { EMIT(KEYWORD_, FUNCTION_, FUNCTION_); }
"return"    { EMIT(KEYWORD_, RETURN_,   RETURN_);   }
"break"     { EMIT(KEYWORD_, BREAK_,    BREAK_);    }
"continue"  { EMIT(KEYWORD_, CONTINUE_, CONTINUE_); }
"and"       { EMIT(KEYWORD_, AND_,      AND_);      }
"not"       { EMIT(KEYWORD_, NOT_,      NOT_);      }
"or"        { EMIT(KEYWORD_, OR_,       OR_);       }
"local"     { EMIT(KEYWORD_, LOCAL_,    LOCAL_);    }
"true"      { EMIT(KEYWORD_, TRUE_,     TRUE_);     }
"false"     { EMIT(KEYWORD_, FALSE_,    FALSE_);    }
"nil"       { EMIT(KEYWORD_, NIL_,      NIL_);      }


"=="        { EMIT(OPERATOR_, EQUAL_,         EQUAL_);         }
"!="        { EMIT(OPERATOR_, NOT_EQUAL_,     NOT_EQUAL_);     }
">="        { EMIT(OPERATOR_, GREATER_EQUAL_, GREATER_EQUAL_); }
"<="        { EMIT(OPERATOR_, LESS_EQUAL_,    LESS_EQUAL_);    }
"++"        { EMIT(OPERATOR_, INCREMENT_,     INCREMENT_);     }
"--"        { EMIT(OPERATOR_, DECREMENT_,     DECREMENT_);     }
"="         { EMIT(OPERATOR_, ASSIGN_,        ASSIGN_);        }
"+"         { EMIT(OPERATOR_, PLUS_,          PLUS_);          }
"-"         { EMIT(OPERATOR_, MINUS_,         MINUS_);         }
"*"         { EMIT(OPERATOR_, MULTIPLY_,      MULTIPLY_);      }
"/"         { EMIT(OPERATOR_, DIVIDE_,        DIVIDE_);        }
"%"         { EMIT(OPERATOR_, MODULUS_,       MODULUS_);       }
">"         { EMIT(OPERATOR_, GREATER_THAN_,  GREATER_THAN_);  }
"<"         { EMIT(OPERATOR_, LESS_THAN_,     LESS_THAN_);     }


"{"         { EMIT(PUNCTUATION_, LEFT_BRACE_,             LEFT_BRACE_);             }
"}"         { EMIT(PUNCTUATION_, RIGHT_BRACE_,            RIGHT_BRACE_);            }
"["         { EMIT(PUNCTUATION_, LEFT_SQUARE_BRACKET_,    LEFT_SQUARE_BRACKET_);    }
"]"         { EMIT(PUNCTUATION_, RIGHT_SQUARE_BRACKET_,   RIGHT_SQUARE_BRACKET_);   }
"("         { EMIT(PUNCTUATION_, LEFT_PARENTHESIS_,       LEFT_PARENTHESIS_);       }
")"         { EMIT(PUNCTUATION_, RIGHT_PARENTHESIS_,      RIGHT_PARENTHESIS_);      }
"::"        { EMIT(PUNCTUATION_, DOUBLE_COLON_,           DOUBLE_COLON_);           }
":"         { EMIT(PUNCTUATION_, COLON_,                  COLON_);                  }
".."        { EMIT(PUNCTUATION_, DOUBLE_DOT_,             DOUBLE_DOT_);             }
"."         { EMIT(PUNCTUATION_, DOT_,                    DOT_);                    }
";"         { EMIT(PUNCTUATION_, SEMICOLON_,              SEMICOLON_);              }
","         { EMIT(PUNCTUATION_, COMMA_,                  COMMA_);                  }

{DIGIT}+    { EMIT(INTCONST_,    NO_SUB_CATEGORY_,        INTCONST_);      }
{REAL}      { EMIT(REALCONST_,   NO_SUB_CATEGORY_,        REALCONST_);     }
{ID}        { EMIT(IDENTIFIER_,  NO_SUB_CATEGORY_,        IDENTIFIER_);    }

\"          {
                string_starting_line = yylineno;
                string_cap = INITIAL_STRING_CAP;
                string_ptr = (char*)malloc(sizeof(char)*INITIAL_STRING_CAP);
                if(!string_ptr)
                {
                    fprintf(stderr, "[ERROR]: Allocation of string at line %d failed", yylineno);
                    exit(-1);
                }
                string_index = 0;
                BEGIN(STRING_STATE);
            }

<STRING_STATE>{
    \"      {
                string_ptr[string_index] = '\0';
                emit(yylval, string_starting_line, string_ptr, STRING_, NO_SUB_CATEGORY_, STRING_);
                free(string_ptr);
                string_ptr = NULL;
                BEGIN(INITIAL);
                return STRING_;
            }

    /* Recognised escape sequences */
    \\n     { growStringBuffer(); string_ptr[string_index++] = '\n'; }
    \\t     { growStringBuffer(); string_ptr[string_index++] = '\t'; }
    \\\"    { growStringBuffer(); string_ptr[string_index++] = '"';  }
    \\\\    { growStringBuffer(); string_ptr[string_index++] = '\\'; }
    \\r     { growStringBuffer(); string_ptr[string_index++] = '\r'; }
    \\b     { growStringBuffer(); string_ptr[string_index++] = '\b'; }
    \\f     { growStringBuffer(); string_ptr[string_index++] = '\f'; }
    \\v     { growStringBuffer(); string_ptr[string_index++] = '\v'; }
    \\a     { growStringBuffer(); string_ptr[string_index++] = '\a'; }
    \\0     { growStringBuffer(); string_ptr[string_index++] = '\0'; }

    \\[^\n] {
                free(string_ptr);
                string_ptr = NULL;

                // Drain Remaining trash
                int c; while ((c = input()) != EOF && c != '"' && c != '\n') {}

                BEGIN(INITIAL);

                return emit(yylval, string_starting_line, NULL, UNIDENTIFIED_, NO_SUB_CATEGORY_, UNIDENTIFIED_);
            }       

    <<EOF>> {
                free(string_ptr);
 
                BEGIN(INITIAL);
                return emit(yylval, string_starting_line, NULL, UNIDENTIFIED_, NO_SUB_CATEGORY_, UNIDENTIFIED_);
            }

    /* Any other character */
    .|\n  { growStringBuffer(); string_ptr[string_index++] = yytext[0]; }
}

"//".*      { return emit(yylval, yylineno, "", COMMENT_, LINE_COMMENT_, COMMENT_);}

"/*"        {
                block_comment_is_nested = false;
                block_comment_depth = 1; 
                block_comment_starting_line = yylineno;
                BEGIN(NESTED_COMMENT_STATE);
            }

<NESTED_COMMENT_STATE>{
    "/*"    {
                block_comment_depth++;
                block_comment_is_nested = true;
            }

    "*/"    {
                if((--block_comment_depth) == 0){
                    BEGIN(INITIAL);
                    return emit(yylval, block_comment_starting_line, "", COMMENT_, (block_comment_is_nested)?NESTED_COMMENT_:BLOCK_COMMENT_, COMMENT_);
                }
            }

    .|\n    { /* Consume */ }

    <<EOF>> { 
                BEGIN(INITIAL);
                return emit(yylval, block_comment_starting_line, "", UNIDENTIFIED_, NO_SUB_CATEGORY_,UNIDENTIFIED_);
            }
}
[ \t\n\r\f\v]+      { /* IGNORE */}

<INITIAL><<EOF>>    { return -1; }

.           { EMIT(UNIDENTIFIED_,NO_SUB_CATEGORY_        ,UNIDENTIFIED_);}

%%