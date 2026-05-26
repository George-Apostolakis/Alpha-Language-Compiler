#ifndef PHASE1FUNCTIONS_H
#define PHASE1FUNCTIONS_H

#include "alpha_lexer.h"

/* All declarations are already in alpha_lexer.h.
   This file exists for Phase-1-specific helpers that are
   not part of the core lexer interface. */

void growStringBuffer(void);

extern int syntax_errors;

#endif /* PHASE1FUNCTIONS_H */