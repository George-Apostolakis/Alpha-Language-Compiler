cmake_minimum_required(VERSION 3.10)
project(ProjectPhase1 C)

# 1) FLEX
find_package(FLEX REQUIRED)

# 2) Include source & build dirs to find alpha_lexer.h and alpha_lexer.c
include_directories(
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_BINARY_DIR}
)

# 3) Generates alpha_lexer.c στο build dir
FLEX_TARGET(Lexer
        ${CMAKE_CURRENT_SOURCE_DIR}/alpha_lexer.l
        ${CMAKE_CURRENT_BINARY_DIR}/alpha_lexer.c
)

# 4) Generates executable 'al'
add_executable(al
        ${CMAKE_CURRENT_SOURCE_DIR}/al.c             # αν χρησιμοποιείς το δικό σου al.c
        ${CMAKE_CURRENT_SOURCE_DIR}/Phase1Functions.c
        ${FLEX_Lexer_OUTPUTS}                        # το παραγόμενο .c από το FLEX
)

# 5) Compiler Flags
target_compile_options(al PRIVATE -Wall -Wextra -g)
