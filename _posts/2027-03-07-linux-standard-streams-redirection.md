---
title: "Standard Streams and Shell Redirection in Linux and C"
date: 2027-03-07
categories: [Linux, Programming]
tags: [linux, c, shell, stdin, stdout, stderr, redirection, unix]
---

# Standard Streams and Shell Redirection in Linux and C

Standard streams form the foundation of Unix input/output operations. Understanding these streams and their redirection mechanisms enables effective command-line workflows and robust C program design.

## Technical Background

### File Descriptors and Standard Streams

In Unix-like operating systems, every open file, socket, or I/O channel receives a file descriptor—a non-negative integer that serves as a handle for the resource. Three file descriptors are automatically available to every process:

| Stream | File Descriptor | Default Connection | Purpose |
|--------|----------------|-------------------|---------|
| `stdin` | 0 | Keyboard (TTY) | Standard input |
| `stdout` | 1 | Terminal screen | Standard output |
| `stderr` | 2 | Terminal screen | Error output |

### TTY and Terminal Association

When a process starts in a terminal session, the kernel associates these file descriptors with the controlling terminal (TTY). This design enables:

- Interactive input from the keyboard through `stdin`
- Normal program output through `stdout`
- Diagnostic and error messages through `stderr`

The separation of `stdout` and `stderr` allows error messages to remain visible even when normal output is redirected to a file or piped to another command.

---

## Shell Redirection Operators

The shell provides operators to redirect standard streams to files or other destinations.

### Input Redirection: `<`

The `<` operator redirects the contents of a file to a command's standard input.

```bash
grep keyword < input.txt
```

This command searches for "keyword" in `input.txt` rather than reading from the keyboard.

### Output Redirection: `>`

The `>` operator redirects standard output to a file, creating the file if it does not exist or truncating it if it does.

```bash
ls > output.txt
```

The directory listing appears in `output.txt` instead of the terminal.

### Error Redirection: `2>`

The `2>` operator redirects standard error to a file.

```bash
cat non-existent.txt 2> error.log
```

Error messages from the failed `cat` command are written to `error.log` while the terminal remains clean.

### Append Mode: `>>`

The `>>` operator appends output to a file rather than truncating it.

```bash
echo "New entry" >> log.txt
```

Repeated execution adds lines to `log.txt` without overwriting existing content.

---

## Combining Redirections

Complex redirection patterns enable fine-grained control over command output.

### Redirect Both Streams: `&>`

The `&>` operator redirects both `stdout` and `stderr` to the same file.

```bash
command &> output.log
```

All output—normal and error—appears in `output.log`.

### Append Both Streams: `&>>`

The `&>>` operator appends both streams to a file.

```bash
command &>> output.log
```

> **Note**: The `&>>` operator is not available in all shells. The portable alternative is `command >> file.txt 2>&1`.

### Redirect stderr to stdout: `2>&1`

The `2>&1` construct redirects file descriptor 2 (`stderr`) to wherever file descriptor 1 (`stdout`) currently points.

```bash
command > output.txt 2>&1
```

This pattern captures both streams in `output.txt`. Order matters: the `stdout` redirection must appear before `2>&1`.

### Separate Files for Each Stream

Distinct files can capture each stream independently.

```bash
command > output.txt 2> errors.txt
```

Normal output goes to `output.txt`; errors go to `errors.txt`.

---

## Output Splitting with tee

The `tee` command reads from standard input and writes to both standard output and one or more files simultaneously.

### Basic Usage

```bash
command | tee file.txt
```

Output appears on the terminal and is also written to `file.txt`.

### Capturing stderr Through tee

To pass `stderr` through `tee`, first redirect it to `stdout`.

```bash
command 2>&1 | tee file.txt
```

Both normal and error output appear on the terminal and in `file.txt`.

### Append Mode with tee

The `-a` flag enables append mode.

```bash
command | tee -a log.txt
```

Output appends to `log.txt` rather than overwriting it.

---

## C Programming with Standard Streams

ANSI C represents the three standard streams as file pointers defined in `<stdio.h>`.

### File Pointers

| Pointer | Description |
|---------|-------------|
| `stdin` | Standard input stream |
| `stdout` | Standard output stream |
| `stderr` | Standard error stream |

### Reading from stdin

The `fgets()` function reads a line from an input stream.

```c
#include <stdio.h>

int main(void) {
    char input[100];

    printf("Enter text: ");
    fgets(input, sizeof(input), stdin);
    printf("Received: %s", input);

    return 0;
}
```

The `scanf()` function provides formatted input parsing.

```c
int value;
scanf("%d", &value);
```

### Writing to stdout

The `printf()` function writes formatted output to `stdout`.

```c
printf("Hello, world!\n");
```

The `fputs()` function writes a string to a specified stream.

```c
fputs("Output line\n", stdout);
```

### Writing to stderr

The `fprintf()` function writes formatted output to any stream, including `stderr`.

```c
fprintf(stderr, "Error: file not found\n");
```

Using `stderr` for error messages ensures they remain visible even when `stdout` is redirected.

```c
#include <stdio.h>

int main(void) {
    FILE *fp = fopen("nonexistent.dat", "r");

    if (fp == NULL) {
        fprintf(stderr, "Error: cannot open file\n");
        return 1;
    }

    /* Normal processing */
    fclose(fp);
    return 0;
}
```

### Stream Redirection with freopen()

The `freopen()` function redirects a standard stream to a file within a C program.

```c
freopen("output.txt", "w", stdout);
printf("This goes to output.txt\n");
```

The `"w"` mode truncates the file; `"a"` appends to it.

### Buffer Flushing

Standard streams are buffered, meaning output may not appear immediately. The `fflush()` function forces buffered data to be written.

```c
printf("Processing...");
fflush(stdout);
/* Long operation */
printf("Done.\n");
```

Without `fflush()`, the "Processing..." message may not appear until the buffer fills or the program terminates.

---

## Common Patterns and Pitfalls

### Pattern: Logging with Timestamps

```bash
command 2>&1 | while read line; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') $line"
done | tee -a application.log
```

### Pattern: Silent Execution with Error Capture

```bash
command > /dev/null 2> errors.txt
```

Normal output is discarded; only errors are preserved.

### Pattern: Discard All Output

```bash
command > /dev/null 2>&1
```

Both streams are redirected to `/dev/null`, the null device that discards all data.

### Pitfall: Incorrect Redirection Order

```bash
# Incorrect: stderr goes to terminal, not file
command 2>&1 > output.txt

# Correct: both streams go to file
command > output.txt 2>&1
```

The `2>&1` duplicates the current destination of `stdout`. If `stdout` has not yet been redirected, `stderr` goes to the terminal.

### Pitfall: Buffering in Pipelines

When piping output to another command, line buffering may switch to block buffering, causing delays.

```bash
# May buffer output unexpectedly
long_running_command | tee log.txt

# Force line buffering
stdbuf -oL long_running_command | tee log.txt
```

### Pitfall: Missing fflush() Before fork()

In C programs that fork child processes, unflushed buffers can cause duplicated output.

```c
printf("Parent message");
/* Missing fflush(stdout); */
fork();  /* Both processes may output "Parent message" */
```

### Pitfall: Mixing printf() and write()

Mixing buffered I/O (`printf`) with unbuffered I/O (`write`) can produce unexpected output order.

```c
printf("First");           /* Buffered */
write(1, "Second\n", 7);   /* Immediate */
printf(" line\n");         /* Buffered */
/* Output: "Second\nFirst line\n" */
```

---

## Summary

Standard streams provide a uniform interface for program input and output. Key concepts include:

- **Three streams**: `stdin` (fd 0), `stdout` (fd 1), `stderr` (fd 2)
- **Shell redirection**: `<`, `>`, `2>`, `&>`, `>>`, `2>&1`
- **Output splitting**: `tee` for simultaneous file and terminal output
- **C file pointers**: `stdin`, `stdout`, `stderr` with `printf()`, `fprintf()`, `fgets()`
- **Buffering awareness**: Use `fflush()` when immediate output is required

Mastery of these fundamentals enables construction of robust command pipelines and well-behaved C programs that integrate properly with Unix toolchains.
