#include <stdio.h>
#include <stdlib.h>
#include "Phase1Functions.h"
#include "Phase2Functions.h"
#include "parser.tab.h"

/* Global variables  */
TokenList lexList    = NULL;
TokenList syntaxList = NULL;
FILE *input_file  = NULL;
FILE *output_file = NULL;

extern FILE *yyin;
extern int   yylineno;
extern int   token_counter;
extern int   syntax_errors;

/* Helpers  */

static int open_output(const char *out_path) {
    if (out_path) {
        output_file = fopen(out_path, "w");
        if (!output_file) {
            perror("Error creating output file");
            return 1;
        }
    } else {
        output_file = stdout;
    }
    return 0;
}

static void close_files(void) {
    if (input_file)
        fclose(input_file);
    if (output_file && output_file != stdout)
        fclose(output_file);
}

/* My main function */
int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <input_file> [output_file]\n", argv[0]);
        return EXIT_FAILURE;
    }

    const char *in_path  = argv[1];
    const char *out_path = (argc >= 3) ? argv[2] : NULL;

    /* Open output file (or stdout) */
    if (open_output(out_path) != 0)
        return EXIT_FAILURE;

    /* Phase 1: Lexical Analysis */

    FILE *lex_file = fopen(in_path, "r");
    if (!lex_file) {
        perror("Error opening input file for lexical analysis");
        return EXIT_FAILURE;
    }

    yyin = lex_file;

    Token *token = NULL;
    while (alpha_yylex((void **)&token) >= 0) {
        if (token) {
            listAppend(&lexList, token);
            token = NULL;
        }
    }

    fclose(lex_file);
    lex_file = NULL;

    printTokens(lexList, output_file);
    printf("[LEXER] Reached end of file at line %d\n", yylineno);
    printf("[LEXER] Lexical analysis identified %d tokens.\n", token_counter);

    checkForLexicalErrors(lexList);

    /* Phase 2: Syntax Analysis */
    FILE *parse_file = fopen(in_path, "r");
    if (!parse_file) {
        perror("Error opening input file for syntax analysis");
        return EXIT_FAILURE;
    }

    //input_file = parse_file;
    yyin = parse_file;
    //printf("[DEBUG] parse_file=%p  yyin=%p\n", (void*)parse_file, (void*)yyin);
    yylineno = 1;
    token_counter = 0;

    initLibraryFunctions();

    if (yyparse() == 0) {
        if (syntax_errors == 0) {
            fprintf(output_file, "Parsing completed successfully.\n");
        } else {
            fprintf(output_file, "Parsing completed with %d syntax error(s).\n", syntax_errors);
        }
    } else {
        fprintf(output_file, "Parsing failed to complete.\n");
    }

    printSymbolTable();

    destroyTokenList(&lexList);
    destroyTokenList(&syntaxList);

    close_files();
    return EXIT_SUCCESS;
}