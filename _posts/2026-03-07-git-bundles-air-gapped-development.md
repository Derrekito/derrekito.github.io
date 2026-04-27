---
title: "Git Bundles for Air-Gapped Development"
date: 2026-03-07
categories: [Git, DevOps]
tags: [git, git-bundle, air-gap, version-control, merge-conflicts]
---

Most git workflows assume a network connection. Clone from GitHub, push to origin, open a pull request. But entire categories of development happen where no network exists — classified defense systems, industrial control networks, medical devices under regulatory isolation, embedded systems on factory floors, or field deployments where the closest internet connection is a satellite link with 40% packet loss. In these environments, `git bundle` is the mechanism that makes version control work across an air gap.

The `git bundle` command produces a [packed archive](https://git-scm.com/docs/git-pack-objects) that git treats as a remote. A bundle file supports cloning, fetching, and pulling — the same operations you would run against a hosted repository — except the transport is a file on a USB drive instead of a TCP connection. Single or multiple branches can be exported, and commit ranges allow incremental transfers that scale to large repositories.

This tutorial walks through a realistic air-gapped workflow: creating a project, bundling it, cloning on the isolated side, making divergent changes on both sides, resolving the resulting merge conflict, and synchronizing back. The second half covers incremental bundles for ongoing development.

> **Note:** The order of operations in this tutorial is deliberate. Following a different sequence will not reproduce the intended merge conflicts.

## When to Use Bundles (and When Not To)

Git provides several mechanisms for offline code transfer. Bundles are not the only option, and choosing the wrong one creates unnecessary friction.

**Git bundles** package complete repository history — objects, refs, and commit graphs — into a single binary file. The receiving side can clone or pull from it exactly as it would from a remote. Bundles preserve branch structure, merge history, and tags. They handle binary files efficiently because they use git's native packfile format. The tradeoff is that bundles are opaque binary files; you cannot review their contents in a text editor.

**Git patches** (`git format-patch` / `git am`) serialize commits as plaintext diffs. They are human-readable, email-friendly, and work well for submitting small changesets to projects where you lack push access. Patches break down for binary files (the diff format is bulky and fragile for non-text content), and they do not carry branch topology — a patch series flattens merge history into a linear sequence.

**Bare repository on USB** — copying a bare `.git` directory to removable media — works but provides no mechanism for incremental transfer. Every sync copies the entire repository. For small projects this is fine; for repositories with large binary assets or deep history, it becomes impractical.

| Mechanism | Preserves history | Binary-friendly | Incremental | Human-readable |
|-----------|:---:|:---:|:---:|:---:|
| `git bundle` | Yes | Yes | Yes | No |
| `git format-patch` | Partial (linear only) | No | Yes | Yes |
| Bare repo copy | Yes | Yes | No | No |

Use bundles when you need full-fidelity repository transfer across an air gap with support for incremental updates. Use patches when you need to email a small changeset for review. Use a bare repo copy when the repository is small enough that copying everything is acceptable.

## Project Setup

Two directories simulate a workstation with network access and an air-gapped system. In practice, these would be separate machines with a USB drive or approved media serving as the transport layer.

Create the workspace and define path variables:

```bash
mkdir -p workstation/liblog airgap
WORKSTATION=$(pwd)/workstation
AIRGAP=$(pwd)/airgap
```

Change to the project directory and create the source file:

```bash
cd $WORKSTATION/liblog
touch liblog.cpp
```

Populate `liblog.cpp` with the following — a minimal logging class with ANSI color output:

```cpp
#include <iostream>
#include <string>

class Log{
public:
    enum Level{
        LOGERROR, LOGWARN, LOGINFO
    };

private:
    Level m_LogLevel = LOGINFO;
    std::string m_STY_RESET = "\033[0m";      // style: default text
    std::string m_STY_ERR = "\033[31;1m";     // style: red, bold
    std::string m_STY_WARN = "\033[33;1m";    // style: yellow, bold
    std::string m_STY_INFO = "\033[32;1m";    // style: green, bold

public:
    void SetLevel(Level level){
        m_LogLevel = level;
    }

    void Error(std::string message){
        if(m_LogLevel >= LOGERROR){
            std::cout << m_STY_ERR << "[ERROR]: " << m_STY_RESET << message << std::endl;
        }
    }

    void Warn(std::string message){
        if(m_LogLevel >= LOGWARN){
            std::cout << m_STY_WARN << "[WARN]: " << m_STY_RESET << message << std::endl;
        }
    }

    void Info(std::string message){
        if(m_LogLevel >= LOGINFO){
            std::cout << m_STY_INFO << "[INFO]: " << m_STY_RESET << message << std::endl;
        }
    }
};

int main(){
    Log log;
    log.SetLevel(Log::LOGINFO);
    log.Warn("A Warning");
    log.Info("Some Information");
    log.Error("An Error");
}
```

## Initialize the Repository and Create a Bundle

Initialize a git repository and make the first commit:

```bash
git init
git add liblog.cpp
git commit -m "first commit"
```

Create a bundle containing the master branch. The `HEAD` ref must be included explicitly — without it, `git clone` cannot determine which branch to check out and will produce a warning instead of a working copy:

```bash
git bundle create ../liblog.bundle master HEAD
```

Expected output:

```
Enumerating objects: 3, done.
Counting objects: 100% (3/3), done.
Compressing objects: 100% (2/2), done.
Total 3 (delta 0), reused 0 (delta 0)
```

> **Note:** Omitting `HEAD` produces the following warning at clone time:
> ```
> warning: remote HEAD refers to nonexistent ref, unable to checkout.
> ```
> The repository still contains the data, but no working tree is checked out. You would need to manually `git checkout master` after cloning. Refer to [Git References](https://git-scm.com/book/en/v2/Git-Internals-Git-References) for details on HEAD behavior.

Set the bundle file as origin so that future pulls reference it directly. In a real air-gap workflow, this path would point to wherever the bundle lands after transfer — a mount point, a shared directory, or a fixed location on the local filesystem:

```bash
git remote add origin ../liblog.bundle
```

## Verify the Bundle

Before transferring a bundle across an air gap, verify it. The `git bundle verify` command confirms that a bundle is structurally valid and that its commit history is compatible with the receiving repository. This catches corrupted transfers and missing prerequisites before they cause confusing errors during a pull:

```bash
git bundle verify ../liblog.bundle
```

```
The bundle contains these 2 refs:
264ed88549ba00b2e18af35a7a3caaabdb6de2ea refs/heads/master
264ed88549ba00b2e18af35a7a3caaabdb6de2ea HEAD
The bundle records a complete history.
liblog.bundle is okay
```

> **Important:** The verify command checks history compatibility only. It does **not** detect content-level merge conflicts. Two sides of an air gap can modify the same file in incompatible ways, and `verify` will report "okay" because the commit graphs are structurally compatible. Conflicts surface only during the actual merge operation.

## Clone the Bundle on the Air-Gapped Side

In practice, this step happens on the isolated machine after physically transferring the bundle file. Here, a file copy simulates the sneakernet:

```bash
cp $WORKSTATION/liblog.bundle $AIRGAP/
cd $AIRGAP
git clone liblog.bundle
```

```
Cloning into 'liblog'...
Receiving objects: 100% (3/3), done.
```

The cloned repository at `$AIRGAP/liblog/` has its origin set to the bundle file path automatically. This is the path that `git pull origin master` will read from in subsequent operations, so the bundle file must remain at this location (or origin must be updated if it moves).

## Diverge: Changes on Both Sides

Air-gapped development inevitably produces divergent changes. The two sides cannot coordinate in real time, so parallel modifications to the same files are common. The next two subsections introduce independent changes that produce a merge conflict — the scenario every air-gapped team encounters eventually.

### Air-Gapped Side: Move the Class to a Header

On the air-gapped system, a developer decides to refactor the monolithic source file into a header and implementation pair. This is a structural change — the class definition moves to a new file:

```bash
cd $AIRGAP/liblog
git branch feature
git checkout feature
touch liblog.hpp
```

Move the `Log` class and its includes into `liblog.hpp`:

```cpp
#include <iostream>
#include <string>

class Log{
public:
    enum Level{
        LOGERROR, LOGWARN, LOGINFO
    };

private:
    Level m_LogLevel = LOGINFO;
    std::string m_STY_RESET = "\033[0m";      // style: default text
    std::string m_STY_ERR = "\033[31;1m";     // style: red, bold
    std::string m_STY_WARN = "\033[33;1m";    // style: yellow, bold
    std::string m_STY_INFO = "\033[32;1m";    // style: green, bold

public:
    void SetLevel(Level level){
        m_LogLevel = level;
    }

    void Error(std::string message){
        if(m_LogLevel >= LOGERROR){
            std::cout << m_STY_ERR << "[ERROR]: " << m_STY_RESET << message << std::endl;
        }
    }

    void Warn(std::string message){
        if(m_LogLevel >= LOGWARN){
            std::cout << m_STY_WARN << "[WARN]: " << m_STY_RESET << message << std::endl;
        }
    }

    void Info(std::string message){
        if(m_LogLevel >= LOGINFO){
            std::cout << m_STY_INFO << "[INFO]: " << m_STY_RESET << message << std::endl;
        }
    }
};
```

Reduce `liblog.cpp` to the header include and `main()`:

```cpp
#include "liblog.hpp"

int main(){
    Log log;
    log.SetLevel(Log::LOGINFO);
    log.Warn("A Warning");
    log.Info("Some Information");
    log.Error("An Error");
}
```

Commit and merge to master:

```bash
git add liblog.cpp liblog.hpp
git commit -m "moved Log class to liblog.hpp"
git checkout master
git merge feature
```

### Workstation Side: Replace std::string with const char*

Meanwhile, on the workstation — with no knowledge of the air-gapped refactor — a different developer optimizes the logging class by replacing `std::string` with `const char*` to eliminate the `<string>` header dependency. This modifies the same lines that the air-gapped side moved into a new file:

```bash
cd $WORKSTATION/liblog
git branch slimer
git checkout slimer
```

Modify `liblog.cpp` — replace all `std::string` declarations with `const char*` and remove `#include <string>`:

```cpp
#include <iostream>

class Log{
public:
    enum Level{
        LOGERROR, LOGWARN, LOGINFO
    };

private:
    Level m_LogLevel = LOGINFO;
    const char* m_STY_RESET = "\033[0m";      // style: default text
    const char* m_STY_ERR = "\033[31;1m";     // style: red, bold
    const char* m_STY_WARN = "\033[33;1m";    // style: yellow, bold
    const char* m_STY_INFO = "\033[32;1m";    // style: green, bold

public:
    void SetLevel(Level level){
        m_LogLevel = level;
    }

    void Error(const char* message){
        if(m_LogLevel >= LOGERROR){
            std::cout << m_STY_ERR << "[ERROR]: " << m_STY_RESET << message << std::endl;
        }
    }

    void Warn(const char* message){
        if(m_LogLevel >= LOGWARN){
            std::cout << m_STY_WARN << "[WARN]: " << m_STY_RESET << message << std::endl;
        }
    }

    void Info(const char* message){
        if(m_LogLevel >= LOGINFO){
            std::cout << m_STY_INFO << "[INFO]: " << m_STY_RESET << message << std::endl;
        }
    }
};

int main(){
    Log log;
    log.SetLevel(Log::LOGINFO);
    log.Warn("A Warning");
    log.Info("Some Information");
    log.Error("An Error");
}
```

Commit and merge to master:

```bash
git add liblog.cpp
git commit -m "replaced std::string with const char*"
git checkout master
git merge slimer
```

## Bundle from Air-Gapped, Pull on Workstation

When both sides have accumulated changes, the question is where to resolve conflicts. The answer is almost always the workstation. The workstation has better tooling — full IDE support, diff viewers, access to documentation — and fewer operational constraints. The air-gapped system may have restricted software installation, limited screen real estate, or security policies that make interactive conflict resolution impractical.

The workflow: bundle on the air-gapped side, physically transfer the file, pull on the workstation, resolve there.

Create a bundle on the air-gapped side and copy it to the workstation:

```bash
cd $AIRGAP/liblog
git bundle create ../liblog.bundle master HEAD
cp $AIRGAP/liblog.bundle $WORKSTATION/
```

Verify the bundle on the workstation before attempting the merge. This confirms the transfer was not corrupted and that the commit histories are compatible:

```bash
cd $WORKSTATION/liblog
git bundle verify ../liblog.bundle
```

```
The bundle contains these 2 refs:
e861a71... refs/heads/master
e861a71... HEAD
The bundle records a complete history.
../liblog.bundle is okay
```

Pull to trigger the merge:

```bash
git pull origin master
```

```
Auto-merging liblog.cpp
CONFLICT (content): Merge conflict in liblog.cpp
Automatic merge failed; fix conflicts and then commit the result.
```

This is the expected outcome. The workstation modified the class body in `liblog.cpp`; the air-gapped side replaced that entire body with an `#include` directive. Git cannot automatically reconcile these changes.

### Resolve the Merge Conflict

The conflict markers in `liblog.cpp` show two divergent states: the workstation retains the full class definition with `const char*` types, while the air-gapped side replaced the class body with `#include "liblog.hpp"`.

The correct resolution requires understanding the intent of both changes. The air-gapped side performed a structural refactor (separating the class into a header), while the workstation performed a type optimization. Both changes are valid and should be preserved: accept the structural refactor and propagate the type change into the header file.

Set `liblog.cpp` to:

```cpp
#include "liblog.hpp"

int main(){
    Log log;
    log.SetLevel(Log::LOGINFO);
    log.Warn("A Warning");
    log.Info("Some Information");
    log.Error("An Error");
}
```

Set `liblog.hpp` to the `const char*` version:

```cpp
#include <iostream>

class Log{
public:
    enum Level{
        LOGERROR, LOGWARN, LOGINFO
    };

private:
    Level m_LogLevel = LOGINFO;
    const char* m_STY_RESET = "\033[0m";      // style: default text
    const char* m_STY_ERR = "\033[31;1m";     // style: red, bold
    const char* m_STY_WARN = "\033[33;1m";    // style: yellow, bold
    const char* m_STY_INFO = "\033[32;1m";    // style: green, bold

public:
    void SetLevel(Level level){
        m_LogLevel = level;
    }

    void Error(const char* message){
        if(m_LogLevel >= LOGERROR){
            std::cout << m_STY_ERR << "[ERROR]: " << m_STY_RESET << message << std::endl;
        }
    }

    void Warn(const char* message){
        if(m_LogLevel >= LOGWARN){
            std::cout << m_STY_WARN << "[WARN]: " << m_STY_RESET << message << std::endl;
        }
    }

    void Info(const char* message){
        if(m_LogLevel >= LOGINFO){
            std::cout << m_STY_INFO << "[INFO]: " << m_STY_RESET << message << std::endl;
        }
    }
};
```

Commit the resolution:

```bash
git add liblog.cpp liblog.hpp
git commit -m "resolved merge conflict"
```

> **Note:** Git cannot push directly to a bundle file. Bundles are read-only archives. Every time the other side needs updated commits, a new bundle must be created and transferred.

## Sync Back to the Air-Gapped Side

The resolved merge now needs to reach the air-gapped system. Create a fresh bundle from the workstation and transfer it:

```bash
git bundle create ../liblog.bundle master HEAD
cp $WORKSTATION/liblog.bundle $AIRGAP/
```

> **Note:** The bundle file must overwrite the file that the air-gapped repository's origin references. If you change the filename or location, update origin with `git remote set-url origin <new-path>`. Verify the current value with `git config --get remote.origin.url`.

Pull on the air-gapped side:

```bash
cd $AIRGAP/liblog
git pull origin master
```

```
Updating e861a71..154bbf6
Fast-forward
 liblog.hpp | 9 ++++-----
 1 file changed, 4 insertions(+), 5 deletions(-)
```

The fast-forward confirms that the air-gapped side had no additional commits since the last bundle was created. Both repositories are now synchronized with identical history.

## Advanced: Incremental Bundles

Full-repository bundles work for small projects, but they become impractical as repositories grow. A project with hundreds of megabytes of history should not require transferring that entire history on every sync cycle. Git provides several mechanisms for creating incremental bundles that contain only recent commits.

### By Time Range

Bundle the last 10 days of commits on master:

```bash
git bundle create ../liblog_10days.bundle --since=10.days.ago master
```

This is useful for regular sync schedules — if the air gap is bridged weekly, bundling the last 10 days provides a safety margin. Git refuses to create an empty bundle if no commits fall within the specified range:

```
warning: ref 'master' is excluded by the rev-list options
fatal: Refusing to create empty bundle.
```

### By Commit Count

Bundle the last 10 commits of master:

```bash
git bundle create ../liblog_last10.bundle -10 master
```

This is simpler than time-based ranges when you know approximately how many commits were made since the last sync.

### By Tag Reference

Tags provide the most reliable mechanism for incremental bundles. A tag marks the exact commit where the two sides last synchronized, eliminating guesswork about time ranges or commit counts.

Create a tag at the current sync point:

```bash
git tag -f last_sync master
```

After committing new work, bundle only the commits since the tag:

```bash
git bundle create ../liblog_incremental.bundle last_sync..master
```

Git refuses to create an empty bundle if no new commits exist since the tag. After the receiving side pulls the incremental bundle, advance the tag on both sides to the new sync point. This establishes a clean baseline for the next transfer cycle.

### Using an Incremental Bundle

An incremental bundle is not self-contained — it requires that the receiving repository already contains all commits up to the bundle's starting point. If the receiving side is missing prerequisite commits, the bundle will fail verification.

Determine the latest commit on the receiving side:

```bash
cd $AIRGAP/liblog
git rev-parse --short HEAD
```

Use that commit ID as the range start when creating the bundle on the sending side:

```bash
cd $WORKSTATION/liblog
git bundle create ../liblog.bundle <commit-id>..master
```

Copy the bundle to the receiving side and verify before pulling. The verify output lists the bundle's refs and any required prerequisite commits:

```bash
cd $AIRGAP/liblog
git bundle verify ../liblog.bundle
```

If the output reports "okay", the pull will succeed:

```bash
git pull origin master
```

To inspect the incoming commits before merging, separate the fetch and merge operations:

```bash
git fetch origin
git log --oneline ^master origin/master
```

This lists every commit that would be applied by a merge, allowing review before committing to the operation.

## Hazards and Tips

### Undoing a Bad Merge

Do **not** use `git reset --hard HEAD^` to undo a merge after `git pull`. A merge commit has two parents, so `HEAD^` refers to the first parent — which may not be the commit you expect. If the pull advanced HEAD through multiple commits, `HEAD^` takes you back one step in what might be the wrong direction.

Use `git reflog` to locate the exact commit you want to return to:

```bash
git reflog
```

```
264ed88 (HEAD -> master) HEAD@{0}: reset: moving to HEAD^
e861a71 HEAD@{1}: commit: moved Log class to liblog.hpp
264ed88 (HEAD -> master) HEAD@{2}: clone: from liblog.bundle
```

Reset to the desired state using the explicit hash:

```bash
git reset --hard e861a71
```

### Verify vs Merge Conflicts

This distinction is worth emphasizing because it catches people off guard. `git bundle verify` answers the question "can this bundle be applied to my repository?" It checks that prerequisite commits exist and that the packfile is structurally valid. It does **not** answer "will the merge succeed without conflicts?"

To preview conflicts before committing, separate the fetch and merge:

```bash
git fetch origin
git merge origin/master
```

This produces the same result as `git pull` but lets you inspect the incoming changes between steps. If the merge produces conflicts you are not ready to resolve, abort cleanly with `git merge --abort`.

### Origin Management

Bundle-based workflows require explicit attention to the origin remote, since the "remote" is a local file path rather than a URL:

- **Cloning a bundle** sets origin to the bundle file path automatically
- **Repositories created with `git init`** require adding origin manually: `git remote add origin ../liblog.bundle`
- **Moving or renaming the bundle file** requires updating origin: `git remote set-url origin <new-path>`
- **Query the current origin path** with `git config --get remote.origin.url`

A common mistake is placing the new bundle at a different path than the original, then wondering why `git pull origin master` fails silently or reads stale data. Verify origin after every transfer.

### Master vs Main

This tutorial uses `master` as the default branch name. Modern git installations default to `main`. Substitute the branch name in all commands as appropriate. The bundle workflow is identical regardless of branch naming convention.

## References

- [git-bundle documentation](https://git-scm.com/docs/git-bundle)
- [Git Tools - Bundling](https://git-scm.com/book/en/v2/Git-Tools-Bundling)
- [Git Internals - Git References](https://git-scm.com/book/en/v2/Git-Internals-Git-References)
