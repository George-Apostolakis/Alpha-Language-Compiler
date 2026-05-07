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


"=="        { EMIT(OPERATOR, EQUAL,         EQUAL);         }
"!="        { EMIT(OPERATOR, NOT_EQUAL,     NOT_EQUAL);     }
">="        { EMIT(OPERATOR, GREATER_EQUAL, GREATER_EQUAL); }
"<="        { EMIT(OPERATOR, LESS_EQUAL,    LESS_EQUAL);    }
"++"        { EMIT(OPERATOR, INCREMENT,     INCREMENT);     }
"--"        { EMIT(OPERATOR, DECREMENT,     DECREMENT);     }
"="         { EMIT(OPERATOR, ASSIGN,        ASSIGN);        }
"+"         { EMIT(OPERATOR, PLUS,          PLUS);          }
"-"         { EMIT(OPERATOR, MINUS,         MINUS);         }
"*"         { EMIT(OPERATOR, MULTIPLY,      MULTIPLY);      }
"/"         { EMIT(OPERATOR, DIVIDE,        DIVIDE);        }
"%"         { EMIT(OPERATOR, MODULUS,       MODULUS);       }
">"         { EMIT(OPERATOR, GREATER_THAN,  GREATER_THAN);  }
"<"         { EMIT(OPERATOR, LESS_THAN,     LESS_THAN);     }


"{"         { EMIT(PUNCTUATION, LEFT_BRACE,             LEFT_BRACE);             }
"}"         { EMIT(PUNCTUATION, RIGHT_BRACE,            RIGHT_BRACE);            }
"["         { EMIT(PUNCTUATION, LEFT_SQUARE_BRACKET,    LEFT_SQUARE_BRACKET);    }
"]"         { EMIT(PUNCTUATION, RIGHT_SQUARE_BRACKET,   RIGHT_SQUARE_BRACKET);   }
"("         { EMIT(PUNCTUATION, LEFT_PARENTHESIS,       LEFT_PARENTHESIS);       }
")"         { EMIT(PUNCTUATION, RIGHT_PARENTHESIS,      RIGHT_PARENTHESIS);      }
"::"        { EMIT(PUNCTUATION, DOUBLE_COLON,           DOUBLE_COLON);           }
":"         { EMIT(PUNCTUATION, COLON,                  COLON);                  }
".."        { EMIT(PUNCTUATION, DOUBLE_DOT,             DOUBLE_DOT);             }
"."         { EMIT(PUNCTUATION, DOT,                    DOT);                    }
";"         { EMIT(PUNCTUATION, SEMICOLON,              SEMICOLON);              }
","         { EMIT(PUNCTUATION, COMMA,                  COMMA);                  }

{DIGIT}+    { EMIT(INTCONST,    NO_SUB_CATEGORY,        INTCONST);      }
{REAL}      { EMIT(REALCONST,   NO_SUB_CATEGORY,        REALCONST);     }
{ID}        { EMIT(IDENTIFIER,  NO_SUB_CATEGORY,        IDENTIFIER);    }

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
                emit(yylval, string_starting_line, string_ptr, STRING, NO_SUB_CATEGORY, STRING);
                free(string_ptr);
                string_ptr = NULL;
                BEGIN(INITIAL);
                return STRING;
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

                return emit(yylval, string_starting_line, NULL, UNIDENTIFIED, NO_SUB_CATEGORY, UNIDENTIFIED);
            }       

    <<EOF>> {
                free(string_ptr);
 
                BEGIN(INITIAL);
                return emit(yylval, string_starting_line, NULL, UNIDENTIFIED, NO_SUB_CATEGORY, UNIDENTIFIED);
            }

    /* Any other character */
    .|\n  { growStringBuffer(); string_ptr[string_index++] = yytext[0]; }
}

"//".*      { return emit(yylval, yylineno, "", COMMENT, LINE_COMMENT, COMMENT);}

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
                    return emit(yylval, block_comment_starting_line, "", COMMENT, (block_comment_is_nested)?NESTED_COMMENT:BLOCK_COMMENT, COMMENT);
                }
            }

    .|\n    { /* Consume */ }

    <<EOF>> { 
                BEGIN(INITIAL);
                return emit(yylval, block_comment_starting_line, "", UNIDENTIFIED, NO_SUB_CATEGORY,UNIDENTIFIED);
            }
}
[ \t\n\r\f\v]+      { /* IGNORE */}

<INITIAL><<EOF>>    { return -1; }

.           { EMIT(UNIDENTIFIED,NO_SUB_CATEGORY        ,UNIDENTIFIED);}

%%