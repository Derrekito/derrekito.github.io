---
title: "Story Arc Templates for Technical Presentations"
date: 2026-08-30 10:00:00 -0700
categories: [LaTeX, Documentation]
tags: [latex, beamer, presentations, storytelling, technical-writing]
---

Technical presentations often feel flat. Slide decks become linear sequences of facts, data tables, and bullet points without narrative pull. Audiences disengage because there is no tension, no resolution, no emotional arc. This post presents two story arc templates that map classic narrative structures to engineering presentation flow, providing LaTeX Beamer implementations for each.

## Problem Statement

Engineering presentations typically follow a predictable structure: background, methods, results, conclusions. While logical, this structure lacks the narrative elements that make information memorable:

- **No tension**: Without a problem that matters, audiences have no reason to care
- **No stakes**: Data without context is just numbers
- **No transformation**: Conclusions feel disconnected from the journey

Story structure provides these missing elements. A well-structured narrative creates anticipation, builds to a climax, and delivers satisfying resolution.

## Narrative Foundations

The templates presented here draw from established narrative theory:

- **Hero's Journey**: Joseph Campbell's monomyth, documented in *The Hero with a Thousand Faces* (1949), describes a universal pattern found across cultures
- **Man in a Hole**: Kurt Vonnegut's shape-of-stories concept, where a protagonist falls into trouble and climbs back out

These structures are not original to technical communication. The contribution here is mapping them specifically to engineering presentation contexts, with concrete LaTeX Beamer implementations.

## Template 1: Hero's Journey

The Hero's Journey structure suits presentations that introduce new capabilities, architectures, or paradigms. The audience follows a transformation from ordinary state to extraordinary outcome.

### Arc Mapping

| Story Beat | Presentation Element | Slide Purpose |
|------------|---------------------|---------------|
| Ordinary World | Title slide | Establish context and credibility |
| Call to Adventure | Status quo & performance gap | Define the opportunity or need |
| Refusal of the Call | Stakeholder concerns | Acknowledge objections honestly |
| Meeting the Mentor | Prior art & guiding principles | Build on established knowledge |
| Crossing the Threshold | Proposed architecture | Commit to the new approach |
| Tests, Allies, Enemies | Early experiments | Show initial validation |
| Approach to Inmost Cave | Core methodology | Present technical depth |
| The Ordeal | Breakthrough data | Reveal key results |
| Reward | Verified solution | Demonstrate success |
| The Road Back | Integration plan | Address deployment |
| Resurrection | Risk mitigation | Handle remaining concerns |
| Return with Elixir | Future roadmap | Vision beyond current work |

### LaTeX Beamer Implementation

```latex
% hero.tex
% Hero's Journey Template for Technical Presentations
% Based on Campbell's monomyth structure

\documentclass[aspectratio=169]{beamer}
\usetheme{metropolis}

% Metadata
\title{[Project Title]}
\subtitle{A Hero's Journey Through [Domain]}
\author{[Author Name]}
\institute{[Organization]}
\date{\today}

% Arc tracking in footer
\newcommand{\arcstage}[1]{\textcolor{gray}{\scriptsize #1}}

\begin{document}

% ============================================================
% ACT I: DEPARTURE
% ============================================================

% ORDINARY WORLD - Title slide
\begin{frame}
    \titlepage
    \arcstage{Ordinary World}
\end{frame}

% CALL TO ADVENTURE - Status quo and performance gap
\begin{frame}{Current State Assessment}
    \arcstage{Call to Adventure}

    \begin{columns}
        \column{0.5\textwidth}
        \textbf{Baseline Performance}
        \begin{itemize}
            \item Metric A: [current value]
            \item Metric B: [current value]
            \item Metric C: [current value]
        \end{itemize}

        \column{0.5\textwidth}
        \textbf{Target Requirements}
        \begin{itemize}
            \item Metric A: [target value]
            \item Metric B: [target value]
            \item Metric C: [target value]
        \end{itemize}
    \end{columns}

    \vspace{1em}
    \alert{The gap demands a new approach.}
\end{frame}

% REFUSAL OF THE CALL - Stakeholder concerns
\begin{frame}{Acknowledged Concerns}
    \arcstage{Refusal of the Call}

    \textbf{Why This Might Fail}
    \begin{enumerate}
        \item [Concern 1]: [Brief description]
        \item [Concern 2]: [Brief description]
        \item [Concern 3]: [Brief description]
    \end{enumerate}

    \vspace{1em}
    These concerns are valid. The following slides address each directly.
\end{frame}

% MEETING THE MENTOR - Prior art and guiding principles
\begin{frame}{Foundation: Prior Art}
    \arcstage{Meeting the Mentor}

    \textbf{Established Knowledge}
    \begin{itemize}
        \item [Reference 1]: Key insight
        \item [Reference 2]: Key insight
        \item [Reference 3]: Key insight
    \end{itemize}

    \vspace{1em}
    \textbf{Guiding Principles}
    \begin{itemize}
        \item Principle 1
        \item Principle 2
    \end{itemize}
\end{frame}

% ============================================================
% ACT II: INITIATION
% ============================================================

% CROSSING THE THRESHOLD - Proposed architecture
\begin{frame}{Proposed Architecture}
    \arcstage{Crossing the Threshold}

    % Insert architecture diagram here
    \begin{center}
        \textit{[Architecture Diagram]}
    \end{center}

    \textbf{Key Design Decisions}
    \begin{enumerate}
        \item Decision 1: Rationale
        \item Decision 2: Rationale
    \end{enumerate}
\end{frame}

% TESTS, ALLIES, ENEMIES - Early experiments
\begin{frame}{Initial Validation}
    \arcstage{Tests, Allies, Enemies}

    \textbf{Experiment 1: [Name]}
    \begin{itemize}
        \item Setup: [description]
        \item Result: [outcome]
        \item Implication: [what it means]
    \end{itemize}

    \vspace{0.5em}
    \textbf{Unexpected Challenge}
    \begin{itemize}
        \item [Challenge encountered]
        \item [How it was addressed]
    \end{itemize}
\end{frame}

% APPROACH TO INMOST CAVE - Core methodology
\begin{frame}{Core Methodology}
    \arcstage{Approach to Inmost Cave}

    \textbf{Technical Approach}
    \begin{enumerate}
        \item Step 1: [description]
        \item Step 2: [description]
        \item Step 3: [description]
    \end{enumerate}

    \vspace{0.5em}
    \textbf{Critical Parameters}
    \begin{itemize}
        \item Parameter A: [value and justification]
        \item Parameter B: [value and justification]
    \end{itemize}
\end{frame}

% THE ORDEAL - Breakthrough data
\begin{frame}{Breakthrough Results}
    \arcstage{The Ordeal}

    % Insert key data visualization here
    \begin{center}
        \textit{[Key Results Figure]}
    \end{center}

    \textbf{Critical Finding}
    \begin{itemize}
        \item [The breakthrough insight]
        \item [Statistical significance]
    \end{itemize}
\end{frame}

% REWARD - Verified solution
\begin{frame}{Verified Solution}
    \arcstage{Reward}

    \textbf{Performance Against Targets}
    \begin{itemize}
        \item Metric A: [achieved] vs [target] \checkmark
        \item Metric B: [achieved] vs [target] \checkmark
        \item Metric C: [achieved] vs [target] \checkmark
    \end{itemize}

    \vspace{0.5em}
    \textbf{Validation Method}
    \begin{itemize}
        \item [How results were verified]
    \end{itemize}
\end{frame}

% ============================================================
% ACT III: RETURN
% ============================================================

% THE ROAD BACK - Integration plan
\begin{frame}{Integration Plan}
    \arcstage{The Road Back}

    \textbf{Deployment Timeline}
    \begin{enumerate}
        \item Phase 1 (Q1): [activities]
        \item Phase 2 (Q2): [activities]
        \item Phase 3 (Q3): [activities]
    \end{enumerate}

    \textbf{Dependencies}
    \begin{itemize}
        \item [Dependency 1]
        \item [Dependency 2]
    \end{itemize}
\end{frame}

% RESURRECTION - Risk mitigation
\begin{frame}{Risk Mitigation}
    \arcstage{Resurrection}

    \begin{tabular}{lll}
        \textbf{Risk} & \textbf{Likelihood} & \textbf{Mitigation} \\
        \hline
        Risk 1 & Medium & [Strategy] \\
        Risk 2 & Low & [Strategy] \\
        Risk 3 & Medium & [Strategy] \\
    \end{tabular}

    \vspace{1em}
    \textbf{Contingency}: [Fallback plan if major risk materializes]
\end{frame}

% RETURN WITH ELIXIR - Future roadmap
\begin{frame}{Future Roadmap}
    \arcstage{Return with Elixir}

    \textbf{Immediate Next Steps}
    \begin{itemize}
        \item [Action 1]
        \item [Action 2]
    \end{itemize}

    \textbf{Long-term Vision}
    \begin{itemize}
        \item [Vision element 1]
        \item [Vision element 2]
    \end{itemize}

    \vspace{0.5em}
    \alert{The capability demonstrated here enables [broader impact].}
\end{frame}

% Questions
\begin{frame}{Questions}
    \centering
    \Large Questions?

    \vspace{1em}
    \normalsize
    Contact: [email] \\
    Repository: [URL]
\end{frame}

\end{document}
```

## Template 2: Man in a Hole

The Man in a Hole structure suits debugging narratives, failure analysis, and problem-solving presentations. The audience follows a descent into crisis and the climb back to stability.

### Arc Mapping

| Story Beat | Presentation Element | Slide Purpose |
|------------|---------------------|---------------|
| Comfortable State | Baseline success | Establish what was working |
| Descent Begins | Emerging issue | First signs of trouble |
| In the Hole | Critical failure point | The crisis moment |
| Turning Point | Resolution strategy | The insight that changed everything |
| Climbing Out | Implementation & tests | Step-by-step recovery |
| Emergence | Validated solution | Proof that the fix works |
| Higher Ground | Improved state | Better than before |
| Lessons & Outlook | Future work | What was learned and what comes next |

### LaTeX Beamer Implementation

```latex
% man_in_a_hole.tex
% Man in a Hole Template for Technical Presentations
% Based on Vonnegut's shape-of-stories concept

\documentclass[aspectratio=169]{beamer}
\usetheme{metropolis}

% Metadata
\title{[Issue Title]: Root Cause and Resolution}
\subtitle{A Debugging Journey}
\author{[Author Name]}
\institute{[Organization]}
\date{\today}

% Arc tracking with fortune indicator
\newcommand{\fortune}[1]{%
    \begin{tikzpicture}[baseline=-0.5ex]
        \draw[gray, thick] (0,0) -- (0.5,0);
        \fill[#1] (0.25,0) circle (2pt);
    \end{tikzpicture}
}
\usepackage{tikz}

\begin{document}

% ============================================================
% DESCENT
% ============================================================

% COMFORTABLE STATE - Baseline success
\begin{frame}
    \titlepage
\end{frame}

\begin{frame}{Baseline: Everything Was Working}
    \fortune{green} \textit{Fortune: High}

    \textbf{System State (Before)}
    \begin{itemize}
        \item Metric A: [good value]
        \item Metric B: [good value]
        \item Uptime: [impressive number]
    \end{itemize}

    \vspace{0.5em}
    \textbf{Context}
    \begin{itemize}
        \item [Relevant background]
        \item [Why baseline matters]
    \end{itemize}
\end{frame}

% DESCENT BEGINS - Emerging issue
\begin{frame}{First Signs of Trouble}
    \fortune{yellow} \textit{Fortune: Declining}

    \textbf{Initial Symptoms}
    \begin{itemize}
        \item [Date/Time]: [First anomaly observed]
        \item [Date/Time]: [Pattern emerging]
        \item [Date/Time]: [Escalation trigger]
    \end{itemize}

    \vspace{0.5em}
    \textbf{Initial Hypotheses}
    \begin{enumerate}
        \item [Hypothesis 1] -- later ruled out
        \item [Hypothesis 2] -- later ruled out
        \item [Hypothesis 3] -- partially correct
    \end{enumerate}
\end{frame}

% IN THE HOLE - Critical failure point
\begin{frame}{Critical Failure}
    \fortune{red} \textit{Fortune: Low Point}

    \textbf{Failure Mode}
    \begin{itemize}
        \item [Precise description of failure]
        \item Impact: [quantified damage]
        \item Duration: [time in failed state]
    \end{itemize}

    \vspace{0.5em}
    \textbf{Contributing Factors}
    \begin{enumerate}
        \item [Factor 1]
        \item [Factor 2]
        \item [Factor 3]
    \end{enumerate}

    \alert{This was the lowest point. The path forward was unclear.}
\end{frame}

% ============================================================
% TURNING POINT
% ============================================================

% TURNING POINT - Resolution strategy
\begin{frame}{The Breakthrough Insight}
    \fortune{yellow} \textit{Fortune: Turning}

    \textbf{Root Cause Identification}
    \begin{itemize}
        \item [The actual root cause]
        \item Evidence: [How it was confirmed]
    \end{itemize}

    \vspace{0.5em}
    \textbf{Resolution Strategy}
    \begin{enumerate}
        \item [Step 1]: [rationale]
        \item [Step 2]: [rationale]
        \item [Step 3]: [rationale]
    \end{enumerate}

    \textit{This insight changed the trajectory of the investigation.}
\end{frame}

% ============================================================
% ASCENT
% ============================================================

% CLIMBING OUT - Implementation and tests
\begin{frame}{Implementation: Climbing Out}
    \fortune{green!50!yellow} \textit{Fortune: Rising}

    \textbf{Fix Implementation}
    \begin{enumerate}
        \item [Change 1]: [description]
        \item [Change 2]: [description]
        \item [Change 3]: [description]
    \end{enumerate}

    \vspace{0.5em}
    \textbf{Verification Tests}
    \begin{itemize}
        \item Test A: [result]
        \item Test B: [result]
        \item Test C: [result]
    \end{itemize}
\end{frame}

% EMERGENCE - Validated solution
\begin{frame}{Validated Resolution}
    \fortune{green} \textit{Fortune: Recovered}

    \textbf{Before vs After}
    \begin{columns}
        \column{0.5\textwidth}
        \textbf{During Failure}
        \begin{itemize}
            \item Metric A: [bad]
            \item Metric B: [bad]
        \end{itemize}

        \column{0.5\textwidth}
        \textbf{After Fix}
        \begin{itemize}
            \item Metric A: [good]
            \item Metric B: [good]
        \end{itemize}
    \end{columns}

    \vspace{0.5em}
    \textbf{Validation Period}: [Duration of post-fix monitoring]
\end{frame}

% HIGHER GROUND - Improved state
\begin{frame}{Higher Ground: Better Than Before}
    \fortune{green!80!blue} \textit{Fortune: Above Baseline}

    \textbf{Improvements Beyond Recovery}
    \begin{itemize}
        \item [Improvement 1]: [quantified benefit]
        \item [Improvement 2]: [quantified benefit]
        \item [Improvement 3]: [quantified benefit]
    \end{itemize}

    \vspace{0.5em}
    \textbf{New Safeguards}
    \begin{itemize}
        \item [Safeguard 1]: Prevents recurrence
        \item [Safeguard 2]: Enables early detection
    \end{itemize}
\end{frame}

% LESSONS AND OUTLOOK - Future work
\begin{frame}{Lessons Learned}

    \textbf{What Went Wrong}
    \begin{enumerate}
        \item [Lesson 1]
        \item [Lesson 2]
    \end{enumerate}

    \textbf{What Went Right}
    \begin{enumerate}
        \item [Lesson 1]
        \item [Lesson 2]
    \end{enumerate}

    \textbf{Future Work}
    \begin{itemize}
        \item [Follow-up action 1]
        \item [Follow-up action 2]
    \end{itemize}
\end{frame}

% Questions
\begin{frame}{Questions}
    \centering
    \Large Questions?

    \vspace{1em}
    \normalsize
    Incident Report: [Link] \\
    Contact: [email]
\end{frame}

\end{document}
```

## Arc Selection Guidelines

Selecting the appropriate arc depends on the presentation's core narrative:

### Use Hero's Journey When:

- Introducing a new capability, product, or architecture
- Presenting research that advances the state of the art
- Proposing a significant change in direction
- The story is fundamentally about transformation and growth
- Stakeholder buy-in requires addressing concerns explicitly

### Use Man in a Hole When:

- Conducting post-incident review or failure analysis
- Presenting debugging journeys and root cause analysis
- Describing recovery from system failures
- The story is fundamentally about problem-solving
- The audience needs to understand what went wrong and why

### Hybrid Approaches

Some presentations combine elements of both arcs. A new feature development that encountered significant obstacles might use Hero's Journey structure with Man in a Hole elements during the "Tests, Allies, Enemies" and "Ordeal" phases.

## Implementation Notes

### Customizing the Templates

Both templates use the Metropolis Beamer theme for clean, modern aesthetics. Modifications for organizational branding:

```latex
% Custom colors
\definecolor{corpblue}{RGB}{0,51,102}
\setbeamercolor{frametitle}{bg=corpblue}

% Custom logo
\logo{\includegraphics[height=0.8cm]{logo.png}}

% Custom fonts (requires XeLaTeX or LuaLaTeX)
\usefonttheme{professionalfonts}
\setmainfont{Helvetica Neue}
```

### Arc Stage Indicators

The templates include visual indicators of narrative position. These can be removed for formal presentations or enhanced for workshop settings:

```latex
% Minimal indicator
\newcommand{\arcstage}[1]{}  % Disable entirely

% Enhanced indicator with progress bar
\newcommand{\arcstage}[1]{%
    \begin{tikzpicture}[remember picture, overlay]
        \node[anchor=south east] at (current page.south east)
            {\scriptsize\textcolor{gray}{#1}};
    \end{tikzpicture}
}
```

### Timing Considerations

Story arc presentations require appropriate pacing:

| Arc Phase | Recommended Time |
|-----------|------------------|
| Setup (Acts I, descent) | 20-25% |
| Development (Act II, turning point) | 50-55% |
| Resolution (Act III, ascent) | 20-25% |

Rushing the setup undermines tension. Rushing the resolution leaves audiences unsatisfied.

## Theoretical Background

These templates operationalize narrative structures from literary theory:

**Campbell's Monomyth** (Hero's Journey) describes transformation through three acts: Departure, Initiation, and Return. The hero leaves the ordinary world, faces trials, and returns transformed. In technical contexts, this maps to: understanding the problem space, developing and validating a solution, and deploying with lessons learned.

**Vonnegut's Shapes of Stories** describes emotional arcs as curves on a fortune-versus-time graph. "Man in a Hole" is the simplest satisfying shape: start in a good place, fall into trouble, climb back out. In technical contexts, this maps naturally to incident response and debugging narratives.

Neither structure is prescriptive. They provide scaffolding for organizing information in ways that align with how audiences naturally process narratives.

## Summary

Technical presentations gain engagement and memorability when structured around narrative arcs rather than linear fact sequences. The Hero's Journey template suits presentations about new capabilities and transformative change. The Man in a Hole template suits debugging narratives and incident reviews.

Key takeaways:

- **Tension creates engagement**: Define what is at stake before presenting solutions
- **Structure creates clarity**: Audiences know where they are in the narrative
- **Resolution creates satisfaction**: End with the transformation complete

The LaTeX Beamer templates provided here offer ready-to-use starting points. Customize the content while preserving the arc structure to maintain narrative coherence.
