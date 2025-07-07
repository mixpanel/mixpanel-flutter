# Cursor Rules Guide

## Overview

These MDC rules complement the Claude Code context by providing active behavioral guidance during code generation in Cursor. While Claude Code context stores comprehensive knowledge about the codebase, these rules actively shape AI behavior to ensure consistent, high-quality code generation.

## Rule Organization

### Directory Structure
```
.cursor/rules/
├── always/                      # Universal rules (<500 lines total)
│   ├── core-conventions.mdc     # Naming, structure, patterns
│   ├── architecture-principles.mdc # System boundaries, dependencies
│   └── code-quality.mdc         # Testing, docs, error handling
├── components/                  # Auto-attached by file type
│   ├── android-implementation.mdc # **/*.java patterns
│   ├── ios-implementation.mdc    # **/*.swift patterns
│   ├── web-implementation.mdc    # **/*_web.dart patterns
│   ├── test-patterns.mdc        # **/test/**/*.dart patterns
│   └── example-app.mdc          # **/example/lib/**/*.dart patterns
└── workflows/                   # Agent-requested procedures
    ├── new-feature.mdc          # Feature implementation guide
    ├── release-process.mdc      # Version release workflow
    └── testing-workflow.mdc     # Multi-platform testing guide
```

## How Rules Relate to Claude Code Context

| Claude Code Context | Cursor Rules | Purpose |
|-------------------|--------------|---------|
| `.claude/context/discovered-patterns.md` | `/always/core-conventions.mdc` | Enforce discovered naming and coding patterns |
| `.claude/context/architecture/system-design.md` | `/always/architecture-principles.mdc` | Maintain architectural boundaries and separation |
| `.claude/context/workflows/*.md` | `/workflows/*.mdc` | Guide complex multi-step procedures |
| `CLAUDE.md` | All rules | Critical patterns distilled into behavioral rules |

## Rule Categories Explained

### Always Rules (Universal Application)
Applied to **every** code generation. These prevent the most common and critical errors:
- **core-conventions.mdc**: Method naming, validation patterns, async conventions
- **architecture-principles.mdc**: Platform separation, singleton pattern, type safety
- **code-quality.mdc**: Testing requirements, documentation standards, error handling

### Component Rules (Auto-Attached)
Applied automatically when working with specific file types:
- **android-implementation.mdc**: Java/Kotlin patterns for Android platform
- **ios-implementation.mdc**: Swift patterns for iOS platform  
- **web-implementation.mdc**: Dart/JS interop for web platform
- **test-patterns.mdc**: Testing conventions and requirements
- **example-app.mdc**: Example app structure and demonstration patterns

### Workflow Rules (Agent-Requested)
Complex procedures the AI can request when needed:
- **new-feature.mdc**: Step-by-step guide for adding SDK features
- **release-process.mdc**: Version release and publishing workflow
- **testing-workflow.mdc**: Comprehensive multi-platform testing

## Quick Reference

### Core Patterns Enforced

| Pattern | Rule File | Key Requirements |
|---------|-----------|------------------|
| Method Naming | `core-conventions.mdc` | camelCase, verb prefixes (track, register, get) |
| Input Validation | `core-conventions.mdc` | Validate strings before platform calls |
| Error Handling | `core-conventions.mdc` | Fail silently with logging, no exceptions |
| Platform Channels | `architecture-principles.mdc` | Consistent argument structure |
| Type Safety | `architecture-principles.mdc` | Custom codec for DateTime/Uri |
| Testing | `code-quality.mdc` | Validation tests for all methods |

### Platform-Specific Requirements

| Platform | Key Patterns |
|----------|--------------|
| Android | JSONObject conversion, lazy init, null safety |
| iOS | Guard statements, MixpanelType conversion |
| Web | JS interop with @JS, safeJsify for types |

## Usage in Cursor

### Automatic Application
1. Always rules apply to all Flutter/Dart files
2. Component rules apply based on file location
3. The AI selects appropriate patterns without prompting

### Manual Workflow Requests
When implementing complex features:
```
"I need to add a new tracking method to the SDK"
→ AI will use new-feature.mdc workflow

"I need to release version 2.5.0"
→ AI will use release-process.mdc workflow
```

## Maintenance Guidelines

### Updating Rules
1. When patterns evolve, update the corresponding rule file
2. Test by generating code and verifying compliance
3. Keep rules in sync with Claude Code context

### Rule Size Management
- Total always rules must stay under 500 lines
- Consolidate similar patterns
- Move detailed examples to component rules

### Testing Rule Effectiveness
1. Generate code for common tasks
2. Verify it follows all conventions
3. Check that platform-specific code is correct
4. Ensure no critical patterns are missed

## Integration with Development Workflow

1. **New Developer Onboarding**: Point to these rules for behavioral expectations
2. **Code Review**: Reference specific rules when commenting
3. **Pattern Updates**: Update rules when establishing new patterns
4. **CI/CD**: Rules ensure generated code passes automated checks

## Relationship to Other Documentation

- **Claude Code Context**: Comprehensive knowledge base and documentation
- **Cursor Rules**: Active behavioral guidance during code generation
- **CLAUDE.md**: High-level patterns and project overview
- **Example App**: Living documentation of SDK usage

Together, these resources ensure AI-generated code is indistinguishable from code written by experienced team members.