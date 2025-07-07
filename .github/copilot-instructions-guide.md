# GitHub Copilot Instructions Integration Guide

## The AI Assistant Ecosystem for Mixpanel Flutter SDK

Our project leverages three complementary AI systems to enhance developer productivity:

| System | Primary Role | When Active | Best For |
|--------|-------------|-------------|----------|
| **Claude Code** | Knowledge Repository | On-demand via CLI (`cc`) | Deep analysis, architecture decisions, complex refactoring |
| **Cursor** | Active Behavioral Guide | During focused coding | Following patterns, preventing errors in context |
| **Copilot** | Persistent Pair Programmer | Always while typing | Quick completions, enforcing conventions |

### How They Work Together

```
Claude Code (Knowledge) → Cursor Rules (Behavior) → Copilot Instructions (Habits)
     ↓                          ↓                            ↓
Deep SDK understanding   Context-aware guidance      Persistent validation
```

### Practical Examples

#### Example 1: Adding a New Tracking Method

**Copilot** ensures you follow the pattern:
```dart
Future<void> trackPurchase(String productId, double amount) async {
  // Copilot automatically suggests validation
  if (!_MixpanelHelper.isValidString(productId)) {
    developer.log('`trackPurchase` failed: productId cannot be blank', name: 'Mixpanel');
    return;
  }
  
  // Copilot knows the exact platform channel pattern
  await _channel.invokeMethod<void>('trackPurchase', <String, dynamic>{
    'productId': productId,
    'amount': amount,
  });
}
```

**Cursor** would provide context-specific guidance about where to add this method and any related native implementations needed.

**Claude Code** can analyze the entire SDK to determine if this method already exists in another form or suggest the best implementation approach.

#### Example 2: Debugging Platform Channel Issues

**Claude Code** can search across all platform implementations:
```bash
cc "find all platform channel handlers for track methods"
```

**Cursor** helps you navigate the native code with proper patterns.

**Copilot** ensures your fixes follow the established patterns.

### When to Update Each System

#### New Pattern Discovered
1. **Universal pattern** (>75% of code)?
   - Add to Copilot instructions immediately
   - Example: New validation helper method

2. **Context-specific pattern**?
   - Document in CLAUDE.md for Claude Code
   - Add Cursor rule if it prevents errors
   - Example: Platform-specific workaround

3. **Complex architectural pattern**?
   - Full documentation in Claude Code context
   - Reference in CLAUDE.md
   - Example: New platform channel codec

#### Common Error Found
1. **Analyze with Claude Code** to understand root cause
2. **Add Copilot instruction** if it's a frequent mistake
3. **Create Cursor rule** for context-aware prevention

### Quick Decision Guide

**Should this go in Copilot instructions?**

✅ **Yes, if:**
- Used in >50% of method implementations
- Prevents SDK breaking changes
- Under 3 lines to explain
- Applies to all platforms

❌ **No, if:**
- Platform-specific implementation detail
- Complex architectural concept
- Requires extensive context
- One-time setup or configuration

### SDK-Specific Integration Points

#### Platform Channel Patterns
- **Copilot**: Enforces the standard invocation pattern
- **Cursor**: Helps implement native handlers
- **Claude Code**: Analyzes all implementations for consistency

#### Type Handling
- **Copilot**: Knows to use `safeJsify()` for web
- **Cursor**: Suggests platform-specific handling
- **Claude Code**: Explains MixpanelMessageCodec implementation

#### Testing
- **Copilot**: Generates tests following SDK patterns
- **Cursor**: Helps with test organization
- **Claude Code**: Analyzes test coverage gaps

### Maintenance Workflow

1. **Monthly Pattern Review**
   - Run Claude Code to analyze new patterns
   - Update Copilot instructions if patterns are now universal
   - Remove outdated patterns

2. **Post-Release Updates**
   - Update version numbers in Copilot instructions
   - Document new features in CLAUDE.md
   - Add Cursor rules for new APIs

3. **Error Pattern Analysis**
   - Use Claude Code to find common PR feedback
   - Add preventive Copilot instructions
   - Create Cursor rules for complex cases

### Tips for Maximum Effectiveness

1. **Let each tool do what it does best**
   - Don't duplicate complex explanations in Copilot
   - Don't make Cursor rules for universal patterns
   - Don't use Claude Code for simple lookups

2. **Keep instructions focused**
   - Copilot: "What to do"
   - Cursor: "How to do it here"
   - Claude Code: "Why we do it this way"

3. **Update regularly but thoughtfully**
   - Not every pattern needs to be in Copilot
   - Quality over quantity
   - Test impact before adding

### Common Pitfalls to Avoid

❌ **Don't add release-specific info to Copilot** (version numbers change)
❌ **Don't duplicate CLAUDE.md content in Copilot** (keep it DRY)
❌ **Don't add complex algorithms to Copilot** (use Claude Code)
❌ **Don't create Cursor rules for universal patterns** (use Copilot)

### Getting Started

1. Copilot automatically loads `.github/copilot-instructions.md`
2. Cursor reads rules from `.cursor/rules/` when present
3. Claude Code accesses `CLAUDE.md` and `.claude/context/`

Each tool enhances your development without interfering with the others. Use them as a suite for maximum productivity!