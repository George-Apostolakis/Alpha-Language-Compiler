/* Imprting c libraries / functions*/
#include <stdio.h>
#include <stdlib.h>
#include "Phase1Functions.h"

/* Global variables */
TokenList lexList   = NULL;
FILE     *input_file  = NULL; //Pointer for input file
FILE     *output_file = NULL;//Pointer for output file

extern FILE *yyin; //Declared in alpa_lexer
extern int   yylineno;//Declared in alpa_lexer
extern int   token_counter;//Declared in alpa_lexer



/* Open input and  output files.Returns 0 on success, 1 on error. */

static int open_files(const char *in_path, const char *out_path) {
    input_file = fopen(in_path, "r");
    if (!input_file) {
        perror("Error opening input file");
        return 1;
    }

    if (out_path) {
        output_file = fopen(out_path, "w");
        if (!output_file) {
            perror("Error creating output file");
            fclose(input_file);
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

    if (open_files(in_path, out_path) != 0)
        return EXIT_FAILURE;

    /* Lexical Anaysis */
    yyin = input_file;

    Token *token = NULL;
    while (alpha_yylex((void **)&token) >= 0) {
        if (token) {
            listAppend(&lexList, token);
            token = NULL;
        }
    }

    /* Printing the results */
    printTokens(lexList, output_file);
    printf("[LEXER] Reached end of file at line %d\n", yylineno);
    printf("[LEXER] Lexical analysis identified %d tokens.\n", token_counter);

    checkForLexicalErrors(lexList);  // Checks and printing lexical erros
    destroyTokenList(&lexList); //Free the tokens list.

    close_files(); //Closing files
    return EXIT_SUCCESS;
}
