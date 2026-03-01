---
title: "liblog: A Lightweight C++ Logging Library with Compile-Time Filtering"
date: 2027-02-21 10:00:00 -0700
categories: [C++, Libraries]
tags: [cpp, logging, library, embedded, cross-platform]
---

Logging libraries in C++ range from minimal single-header solutions to feature-rich frameworks with asynchronous output, log rotation, and network sinks. For projects requiring neither extreme minimalism nor enterprise-scale complexity, a middle ground exists. liblog provides a stream-based logging API with compile-time filtering, colored console output, and file output—all in approximately 200 lines of code with no external dependencies beyond C++11.

## Problem Statement: Why Another Logging Library

The C++ logging ecosystem presents developers with a choice between two extremes. On one end, single-header printf wrappers offer simplicity but lack structured log levels and filtering. On the other end, libraries like spdlog and glog provide extensive features at the cost of build complexity, dependencies, and learning curves.

Three specific requirements drove the development of liblog:

1. **Zero-overhead filtering**: Log statements disabled at compile time should generate no code—not just skip output at runtime, but produce no binary bloat whatsoever.

2. **No external dependencies**: The library must compile with a standard C++11 toolchain. No Boost, no fmt, no system-specific libraries.

3. **Stream-based API**: The logging syntax should feel native to C++ developers, using `<<` operators rather than printf-style format strings.

## Stream-Based API Design

liblog adopts the iostream pattern familiar to C++ developers. Log statements use the global `log()` function with a level parameter, followed by stream insertion operators:

```cpp
#include <liblog.hpp>

int main() {
    log(INFO)  << "Server started on port " << 8080;
    log(WARN)  << "Connection timeout after " << 30 << " seconds";
    log(ERROR) << "Failed to write to database";
    return 0;
}
```

The `log()` function returns a temporary `LogStatement` object that accumulates streamed values into an internal `std::ostringstream`. When the statement ends (at the semicolon), the `LogStatement` destructor triggers, committing the accumulated message to the configured outputs.

This RAII-based design ensures log messages are written even if an exception interrupts execution—no explicit flush calls required.

### STL Container Logging

Optional macros enable direct streaming of STL containers:

```cpp
// Enable with -DENABLE_VECTOR_LOGGING -DENABLE_MAP_LOGGING

std::vector<int> ports = {8080, 8443, 9000};
log(INFO) << "Active ports: " << ports;  // Output: [8080, 8443, 9000]

std::map<std::string, int> stats = {{"errors", 5}, {"warnings", 12}};
log(DEBUG) << "Statistics: " << stats;   // Output: {errors: 5, warnings: 12}
```

These features are compile-time optional to avoid including `<vector>` and `<map>` headers when unused.

## Log Level Hierarchy and ANSI Colors

liblog defines six log levels in ascending severity:

| Level | Numeric | Color  | Purpose |
|-------|---------|--------|---------|
| TRACE | 0 | Gray | Detailed execution tracing |
| DEBUG | 1 | Blue | Development debugging information |
| INFO  | 2 | Green | Normal operational messages |
| WARN  | 3 | Yellow | Warning conditions requiring attention |
| ERROR | 4 | Red | Error conditions, operation failed |
| FATAL | 5 | Red (bold) | Critical failures, application may terminate |

Console output uses ANSI escape sequences for coloring:

```cpp
const std::string LibColor::TraceColor = "\033[1;30m";  // Gray
const std::string LibColor::DebugColor = "\033[1;34m";  // Blue
const std::string LibColor::InfoColor  = "\033[1;32m";  // Green
const std::string LibColor::WarnColor  = "\033[1;93m";  // Yellow
const std::string LibColor::ErrorColor = "\033[1;31m";  // Red
const std::string LibColor::FatalColor = "\033[31;1m";  // Bold red
```

Colors apply only to console (stderr) output. File output receives the same formatted messages without ANSI codes, ensuring log files remain readable in any text editor.

## Compile-Time Filtering Mechanism

The `DEBUG_LEVEL` macro controls which log levels compile into the binary. Unlike runtime filtering that evaluates conditions at every log call, compile-time filtering eliminates disabled log statements entirely.

### How It Works

The Makefile passes `DEBUG_LEVEL` as a compiler definition:

```makefile
DEBUG_LEVEL ?= 1
MACRO_FLAGS += -DDEBUG_LEVEL=$(DEBUG_LEVEL)
```

The header maps this to a threshold:

```cpp
#if DEBUG_LEVEL == 1
    #define LOG_LEVEL TRACE
#elif DEBUG_LEVEL == 2
    #define LOG_LEVEL DEBUG
#elif DEBUG_LEVEL == 3
    #define LOG_LEVEL INFO
#elif DEBUG_LEVEL == 4
    #define LOG_LEVEL WARN
#elif DEBUG_LEVEL == 5
    #define LOG_LEVEL ERROR
#elif DEBUG_LEVEL == 6
    #define LOG_LEVEL FATAL
#endif
```

At runtime, `commitLog()` checks the current log level against this compiled threshold:

```cpp
void LibLog::commitLog(const std::string& message) {
    if (m_level >= m_threshold) {
        m_logStatement.appendToBuffer(message);
        writeLog();
    }
}
```

### Practical Impact

Consider a debug-heavy function:

```cpp
void processPacket(const Packet& p) {
    log(TRACE) << "Entering processPacket";
    log(DEBUG) << "Packet size: " << p.size();
    log(TRACE) << "Header: " << p.header();
    // ... processing logic ...
    log(TRACE) << "Exiting processPacket";
}
```

When compiled with `DEBUG_LEVEL=3` (INFO and above), the compiler can optimize away all four log statements. The binary contains no trace of them—no string literals, no function calls, no conditional jumps. This matters for embedded systems and performance-critical paths where even evaluating a condition thousands of times per second adds up.

## Build System and Cross-Platform Support

The Makefile-based build system produces static (`.a`) and shared (`.so`) libraries:

```bash
# Standard build
make

# Build with INFO level and above only
make DEBUG_LEVEL=3

# Install to /usr/local
sudo make install

# Install to user directory
make install PREFIX=~/.local
```

### Platform-Specific Options

macOS requires `.dylib` shared libraries:

```bash
make mac=1
```

This produces `liblog.a`, `liblog.so`, and `liblog.dylib`.

For ARM64 cross-compilation (embedded Linux, Raspberry Pi):

```bash
make aarch64=1
```

This switches the toolchain to `aarch64-linux-gnu-g++`.

### Integration

After installation, link against the library:

```bash
g++ -std=c++11 application.cpp -llog -o application
```

Or include the source directly for single-file integration:

```bash
g++ -std=c++11 -I/path/to/liblog/src \
    -DDEBUG_LEVEL=3 \
    application.cpp \
    /path/to/liblog/src/liblog.cpp \
    -o application
```

## File Output Implementation

liblog writes to a log file in append mode, creating parent directories automatically:

```cpp
bool create_recursive(const std::string& path) {
    size_t pos = 0;
    while ((pos = path.find('/', pos + 1)) != std::string::npos) {
        std::string dir = path.substr(0, pos);
        if (mkdir(dir.c_str(), 0777) == -1) {
            if (errno != EEXIST) {
                return false;
            }
        }
    }
    return true;
}
```

This enables specifying nested paths like `logs/2027/02/application.log` without manual directory creation.

### Singleton Initialization

The logger initializes on first use via the singleton pattern:

```cpp
LibLog& LibLog::instance(const std::string& fileName, bool consoleOutput) {
    if (m_instance == NULL) {
        m_instance = new LibLog(fileName, consoleOutput);
    }
    return *m_instance;
}
```

The default configuration writes to `output.log` with console output enabled:

```cpp
LibLog::LogStatement log(LogLevel level) {
    static LibLog& logger = LibLog::instance("output.log", true);
    return std::move(logger.getLogStatement(level));
}
```

## Comparison to Alternative Libraries

| Feature | liblog | spdlog | glog | Boost.Log |
|---------|--------|--------|------|-----------|
| Dependencies | None (C++11) | fmt (bundled) | gflags | Boost |
| Compile-time filtering | Yes | Limited | No | Complex |
| Header-only option | No | Yes | No | No |
| Async logging | No | Yes | No | Yes |
| Log rotation | No | Yes | Yes | Yes |
| Binary size impact | Minimal | Moderate | Moderate | Large |
| Build complexity | Make | CMake | CMake/Bazel | b2/CMake |

### When to Use liblog

liblog suits projects that need:

- Simple, predictable logging without configuration files
- Minimal binary size increase (embedded, resource-constrained)
- C++11 compatibility without modern standards requirements
- Quick integration without build system changes

### When to Choose Alternatives

Consider spdlog or glog when requirements include:

- Asynchronous logging (high-throughput applications)
- Log rotation (long-running services)
- Multiple output sinks (files, syslog, network)
- Thread-safe logging (liblog requires external synchronization)

## Extensibility

liblog supports customization through inheritance. Two virtual methods serve as extension points:

### Custom Timestamp Format

```cpp
class ISOLogger : public LibLog {
protected:
    std::string getTimestamp() override {
        auto t = std::time(nullptr);
        char buf[32];
        std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%S", std::localtime(&t));
        return buf;
    }
};
```

### Custom Log Format

```cpp
class JSONLogger : public LibLog {
protected:
    std::stringstream buildLog(const std::string& msg) override {
        std::stringstream ss;
        ss << "{\"timestamp\":" << getTimestamp()
           << ",\"level\":\"" << levelToString(m_level) << "\""
           << ",\"message\":\"" << msg << "\"}\n";
        return ss;
    }
};
```

## Conclusion

liblog occupies a specific niche: projects requiring structured logging with compile-time filtering, minimal dependencies, and straightforward integration. The stream-based API integrates naturally with C++ code, while the `DEBUG_LEVEL` macro ensures production builds carry no overhead from disabled log statements.

For projects where the feature set aligns with requirements, liblog provides a lightweight alternative to heavier logging frameworks. For projects requiring async output, rotation, or thread safety, consider spdlog or glog—but evaluate whether those features justify the additional complexity.
