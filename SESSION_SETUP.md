# dslua Phase 1 Implementation - Session Setup

## Quick Start

You're already in the dslua repository at:
```
/Users/Janis_Vizulis/go/src/github.com/postfix/dslua
```

## To Execute the Implementation Plan

**Start a new Claude Code session** and invoke the executing-plans skill:

```
/superpowers:executing-plans
```

The skill will:
1. Load the implementation plan from `docs/plans/2026-01-28-phase1-core-abstractions.md`
2. Guide you through each task systematically
3. Verify each step before proceeding
4. Commit frequently with clear messages

## What You'll Implement

**Phase 1: Core Abstractions** (10 tasks, ~27 tests)

1. ✅ Field type - Data structure for typed fields
2. ✅ Signature type - Input/output contracts
3. ✅ Context type - Request-scoped data carrier
4. ✅ Module base class - Foundation for all modules
5. ✅ OpenAI provider - LLM provider structure
6. ✅ Predict module - Direct LLM prediction
7. ✅ Main package entry - Public API surface
8. ✅ CLI skeleton - Command-line interface
9. ✅ README update - Documentation
10. ✅ Test suite verification - Final validation

## Current Status

✅ Repository initialized at https://github.com/postfix/dslua
✅ Design document complete (DESIGN.md)
✅ Implementation plan complete (docs/plans/2026-01-28-phase1-core-abstractions.md)
✅ Directory structure created
✅ Ready to implement

## Commands for Reference

```bash
# Run tests
busted -v

# Run specific test file
busted specs/core/field_spec.lua -v

# Check git status
git status

# View recent commits
git log --oneline

# Push to remote
git push origin main
```

## Test-Driven Development Workflow

Each task follows this pattern:
1. Write failing test
2. Run test to verify it fails
3. Write minimal implementation
4. Run test to verify it passes
5. Commit

This ensures:
- ✅ Tests exist before code
- ✅ Code is minimal (YAGNI)
- ✅ Frequent commits for easy rollback
- ✅ Clear progress tracking

## Expected Outcome

After completing all 10 tasks:
- 27 tests passing
- 10 focused commits
- Core abstractions fully working
- Predict module functional
- Ready for Phase 2 (HTTP integration, ChainOfThought, ReAct)

---

**Ready to start? Open a new session and run:**
```
/superpowers:executing-plans
```
