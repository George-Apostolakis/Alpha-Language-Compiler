# Compiler
CC = gcc

# Compiler flags
CFLAGS = -Wall -Wextra

# Target executable
TARGET = main

# Source files
SOURCES = lex.yy.c main.c phase1_src/cat_to_strings.c phase1_src/linked_list.c

# Lex file
LEX_FILE = alpha_lexer.l

# Default rule
all: $(TARGET)

# Rule to build the target executable
$(TARGET): lex.yy.c $(filter-out lex.yy.c, $(SOURCES))
	$(CC) $(CFLAGS) $(SOURCES) -o $(TARGET)

# Rule to generate lex.yy.c from the lex file
lex.yy.c: $(LEX_FILE)
	flex $(LEX_FILE)

# Clean rule to remove generated files
clean:
	rm -f lex.yy.c $(TARGET)

# Phony targets
.PHONY: all clean