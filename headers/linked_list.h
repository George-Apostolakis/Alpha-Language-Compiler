#pragma once
/**
 * @file linkedList.h
 * @brief Dynamic single linked list implementation in C.
 *
 * Provides basic operations for creating, modifying, querying, and freeing
 * linked lists. Designed for educational and general-purpose usage.
 *
 * Author: Giorgos Apostolakis
 * Date: 2025-10-20
 */

#include "token.h"
#include <stdio.h>
#include <stdbool.h>

/* -------------------------------------------------------------------------- */
/*                              Error Code Macros                             */
/* -------------------------------------------------------------------------- */

#define LINKEDLIST_NULL -9999                   /**< Null pointer passed as list. */
#define LINKEDLIST_ALLOCATION_FAILED -9995      /**< Malloc failed */
#define LINKEDLIST_UNIDENTIFIED_TOKENS -9994    /**< UNIDENTIFIED Token in list */
// #define DEBUG

/**
 * @struct List
 * @brief Represents the linked list itself.
 */
typedef struct List List;

/**
 * @brief Creates an empty linked list.
 * @param list a pointer to the list itself
 * @return 1 if process is successful , appropriate MACRO in case of error.
 * @note Caller must call LinkedList_Free() to avoid memory leaks.
 */
int LinkedList_CreateEmpty(List **list);

/**
 * @brief Add a new node at the end of the list.
 * @param list a pointer to the list itself.
 * @param value the value of the new element.
 * @return returns 1 if addition of new element succeeds, Appropriate MACRO in case it fails.
 */
int LinkedList_AddToEnd(List **list, Token value);

/**
 * @brief Gives the size of the list.
 * @param list The list.
 * @return an integer equal to the size of the list, Appropriate MACRO if process fails.
 */
int LinkedList_GetLength(const List *list);

/**
 * @brief Frees all the memory the list has occupied.
 * @param list Pointer to the list itself.
 */
void LinkedList_Free(List **list);

/**
 * @brief Prints the list.
 * @param list the list to print
 * @param out Print output of the list (for example stdout). 
 */
void LinkedList_Print(const List *list, FILE* out);

/**
 * @brief Checks for any UNIDENTFIED tokens and prints appropriate messages.
 * @param[in] list The list.
 * @return 1 if no UNIDENTIFIED tokens are found , LINKEDLIST_UNIDENTIFIED_TOKENS, LINKEDLIST_NULL in case of error.
 */
int LinkedList_CheckErrors(const List *list);