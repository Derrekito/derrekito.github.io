---
title: "Implementing a Singly Linked List in C: A Systems Programming Perspective"
date: 2027-01-17 10:00:00 -0700
categories: [Programming, C]
tags: [c, data-structures, linked-list, pointers, memory-management, systems-programming]
---

Understanding linked lists at the C level provides foundational knowledge for systems programming, operating system internals, and embedded development. While higher-level languages abstract away memory management, C exposes the raw mechanics of how data structures occupy and traverse memory. This post examines a singly linked list implementation, focusing on pointer mechanics and memory allocation patterns.

## Problem Statement

Arrays offer O(1) random access but impose constraints: fixed size at allocation time and O(n) insertion/deletion in the middle. Linked lists trade random access performance for dynamic sizing and efficient insertions. However, the textbook explanation often glosses over the implementation details that cause real confusion:

- Why does modifying the head pointer require a pointer-to-pointer?
- How does `malloc` interact with the node structure?
- What happens to memory when nodes are removed?

A working implementation illuminates these concepts in ways that diagrams alone cannot.

## Technical Background

### Dynamic Memory Allocation

The C standard library provides `malloc()` for heap allocation:

```c
void* malloc(size_t size);
```

This function returns a pointer to `size` bytes of uninitialized memory, or `NULL` on failure. The memory persists until explicitly freed with `free()`. Unlike stack allocation (local variables), heap memory survives function returns.

```c
struct Node* ptr = (struct Node*) malloc(sizeof(struct Node));
```

The `sizeof` operator returns the size in bytes of the structure, ensuring correct allocation regardless of padding or architecture differences.

### Pointer Fundamentals

A pointer stores a memory address. The type determines how dereferencing interprets that address:

```c
int x = 42;
int* ptr = &x;    // ptr holds the address of x
*ptr = 100;       // dereference: modify x through ptr
```

For structures, the arrow operator (`->`) combines dereferencing and member access:

```c
struct Node* n = create_node(10, NULL);
n->data = 20;     // equivalent to (*n).data = 20
```

### Abstract Data Types

A linked list is an abstract data type (ADT) that provides a sequence interface: ordered elements supporting insertion, deletion, and traversal. The underlying implementation uses nodes connected by pointers, but the interface hides this detail from consumers.

## Node Structure Design

The fundamental building block stores data and a pointer to the next node:

```c
struct Node
{
  int data;           // 4 bytes on most systems
  struct Node* next;  // pointer to next node (4 or 8 bytes)
};
```

### Memory Layout

On a 64-bit system with typical alignment:

```
+--------+--------+
|  data  |  next  |
+--------+--------+
| 4 bytes| 8 bytes| = 16 bytes total (with padding)
+--------+--------+
```

The `next` pointer holds the address of another `Node` structure, or `NULL` to indicate the list end.

### Self-Referential Structure

The `struct Node* next` declaration references the structure being defined. This self-reference enables the chain of nodes. The compiler handles this because pointers have a fixed size regardless of what they point to.

## Node Creation Function

```c
struct Node* create_node(int data, struct Node* next)
{
  struct Node* temp = (struct Node*) malloc(sizeof(struct Node));
  temp->data = data;
  temp->next = next;
  return temp;
}
```

### Memory Diagram After `create_node(10, NULL)`

```
Stack                    Heap
+-------+               +-----------+
| temp  | -----------> |  data: 10 |
+-------+               |  next: NULL|
                        +-----------+
                        Address: 0x7f8a (example)
```

The function returns the heap address. The caller must store this address; otherwise, the memory becomes unreachable (a leak).

## The Pointer-to-Pointer Pattern

The most subtle aspect of linked list implementation involves modifying the head or tail pointer. Consider a naive approach:

```c
// INCORRECT: Does not modify caller's head
void prepend_wrong(struct Node* head_ptr, int data)
{
  struct Node* new_node = create_node(data, head_ptr);
  head_ptr = new_node;  // Only modifies local copy
}
```

When called with `prepend_wrong(head, 5)`, C passes the head pointer by value. The function receives a copy. Assigning to `head_ptr` modifies the copy, leaving the caller's `head` unchanged.

### Solution: Double Indirection

```c
void prepend(struct Node** head_ptr, int data)
{
  struct Node* old_head = (*head_ptr);
  struct Node* new_node = create_node(data, NULL);
  (*head_ptr) = new_node;
  (*head_ptr)->next = &(*old_head);
}
```

The parameter `struct Node** head_ptr` is a pointer to a pointer. The function receives the address of the caller's `head` variable, enabling modification through dereferencing.

### Visual Explanation

```
Before prepend(&head, 200):

main()'s stack:          Heap:
+------+                 +-------+       +-------+
| head | -------------> | 10    | ----> | 100   | ---> ...
+------+                 +-------+       +-------+
| tail |                    ^
+------+                    |
                         head points here


prepend() receives:
+----------+
| head_ptr | --------> (address of head in main's stack)
+----------+


After (*head_ptr) = new_node:

main()'s stack:          Heap:
+------+                 +-------+       +-------+       +-------+
| head | -------------> | 200   | ----> | 10    | ----> | 100   | ---> ...
+------+                 +-------+       +-------+       +-------+
| tail |                    ^
+------+                    |
                         head now points here
```

The dereference `(*head_ptr)` accesses the original `head` variable in `main()`, allowing the assignment to persist after `prepend()` returns.

## Implementation Walkthrough

### Initialization

```c
int main()
{
  struct Node* head = NULL;
  struct Node* tail = NULL;

  head = create_node(10, NULL);  // First node
  tail = head;                   // Single node: head == tail
```

Initial state after first node creation:

```
+------+          +-------+
| head | -------> | 10    |
+------+     |    | NULL  |
             |    +-------+
+------+     |
| tail | ----+
+------+
```

Both `head` and `tail` point to the same node. This represents a one-element list.

### Append Operation

```c
void append(struct Node** tail_ptr, int data)
{
  struct Node* new_node = create_node(data, NULL);
  (*tail_ptr)->next = &(*new_node);
  (*tail_ptr) = new_node;
}
```

Step-by-step for `append(&tail, 100)`:

1. `create_node(100, NULL)` allocates new node on heap
2. `(*tail_ptr)->next` accesses the current tail's `next` field
3. Assignment links current tail to new node
4. `(*tail_ptr) = new_node` updates tail to point to new node

```
Before:
tail -> [10|NULL]

After create_node:
tail -> [10|NULL]    [100|NULL] (new_node, unlinked)

After (*tail_ptr)->next = new_node:
tail -> [10| * ]---> [100|NULL]

After (*tail_ptr) = new_node:
        [10| * ]---> [100|NULL] <-- tail
```

### Prepend Operation

```c
void prepend(struct Node** head_ptr, int data)
{
  struct Node* old_head = (*head_ptr);
  struct Node* new_node = create_node(data, NULL);
  (*head_ptr) = new_node;
  (*head_ptr)->next = &(*old_head);
}
```

This operation:
1. Saves the current head address
2. Creates a new node
3. Updates `head` to the new node
4. Links the new node to the old head

### Traversal and Counting

```c
int count_nodes(struct Node* node)
{
  int count = 0;
  while(node->next != NULL)
  {
    count++;
    node = &(*(node->next));
  }
  return count;
}
```

Note: This implementation has an off-by-one issue. The loop terminates when `node->next` is `NULL`, but the final node is not counted. A corrected version:

```c
int count_nodes(struct Node* node)
{
  int count = 0;
  while(node != NULL)
  {
    count++;
    node = node->next;
  }
  return count;
}
```

### Print Functions

```c
void print_list(struct Node** node)
{
  struct Node* temp = *node;

  while(temp->next != NULL)
  {
    printf("%d, ", temp->data);
    temp = &(*(temp->next));
  }
}

void print(struct Node** node)
{
  printf("\n{");
  print_list(node);
  printf("}\n");
}
```

The wrapper function `print()` adds formatting braces around the output.

## Common Pitfalls

### Memory Leaks

Every `malloc()` requires a corresponding `free()`. Without proper cleanup:

```c
// MEMORY LEAK: nodes never freed
int main()
{
  struct Node* head = create_node(1, NULL);
  append(&tail, 2);
  append(&tail, 3);
  return 0;  // Memory leaked
}
```

Proper cleanup requires traversing and freeing each node:

```c
void free_list(struct Node* head)
{
  struct Node* current = head;
  while(current != NULL)
  {
    struct Node* next = current->next;
    free(current);
    current = next;
  }
}
```

The temporary `next` pointer is essential. Freeing `current` before saving `current->next` would access freed memory.

### Dangling Pointers

After `free()`, the pointer still holds the old address, but the memory is invalid:

```c
struct Node* n = create_node(10, NULL);
free(n);
n->data = 20;  // UNDEFINED BEHAVIOR: accessing freed memory
```

Best practice: set pointers to `NULL` after freeing:

```c
free(n);
n = NULL;
```

### NULL Pointer Dereference

Attempting to access members through a `NULL` pointer crashes the program:

```c
struct Node* n = NULL;
n->data = 10;  // CRASH: dereferencing NULL
```

Functions must handle empty lists:

```c
int count_nodes(struct Node* node)
{
  if(node == NULL) return 0;
  // ... rest of implementation
}
```

### Off-by-One Errors

The original `count_nodes` implementation demonstrates this:

```c
while(node->next != NULL)  // Misses the last node
```

The condition checks `next`, causing the loop to exit before counting the final node whose `next` is `NULL`.

## Comparison to Arrays

| Operation | Array | Linked List |
|-----------|-------|-------------|
| Access by index | O(1) | O(n) |
| Insert at beginning | O(n) | O(1) |
| Insert at end | O(1) amortized | O(1) with tail pointer |
| Insert in middle | O(n) | O(1) after finding position |
| Memory overhead | None | Pointer per element |
| Cache locality | Excellent | Poor |
| Size flexibility | Fixed or realloc | Dynamic |

### When to Use Arrays

- Random access patterns dominate
- Size is known at compile time
- Cache performance matters (numerical computing)
- Memory is constrained

### When to Use Linked Lists

- Frequent insertions/deletions at arbitrary positions
- Size varies dramatically
- Implementing other structures (stacks, queues, graphs)
- Memory fragmentation concerns (each node is small)

## Extension Exercises

The original implementation includes TODO markers for additional functions. Each presents distinct challenges:

### `read(int index)`

Return the data at a given index. Requires traversal from head, counting nodes until reaching the target. Must handle out-of-bounds indices.

```c
int read(struct Node* head, int index)
{
  struct Node* current = head;
  int i = 0;
  while(current != NULL && i < index)
  {
    current = current->next;
    i++;
  }
  if(current == NULL)
  {
    // Handle error: index out of bounds
  }
  return current->data;
}
```

### `write(int index, int data)`

Modify the data at a given index. Similar traversal to `read()`, with assignment instead of return.

### `remove(int index)`

Delete the node at a given index. Requires pointer surgery:

1. Find the node before the target
2. Update `previous->next` to skip the target
3. `free()` the removed node
4. Handle edge cases: removing head, removing tail, single-element list

### `pop()`

Remove and return the head element. Must update the head pointer (requiring pointer-to-pointer parameter) and free the old head.

### `insert(int index, int data)`

Insert a new node at a given position. Requires finding the node before the insertion point and updating pointers to splice in the new node.

## Conclusion

Implementing a linked list in C exposes the mechanics of dynamic memory and pointer manipulation that higher-level languages abstract away. The pointer-to-pointer pattern for modifying head/tail references demonstrates how C handles "pass by reference" semantics. Understanding these fundamentals enables effective work with more complex data structures, system programming interfaces, and embedded development where manual memory control is essential.

The complete implementation demonstrates core patterns: heap allocation with `malloc()`, structure self-reference, pointer indirection, and traversal. The extension exercises provide practice with the complementary operations needed for a complete ADT implementation.
