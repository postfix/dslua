# ACE Phase 2 POC - Learning Algorithm Validation

**Status:** Complete ✅

**Purpose:** Validate core Phase 2 learning mechanics in isolation before full ACE integration.

## Overview

This POC tests the learning algorithm correctness using a minimal ACE stub that reuses Phase 1 decision primitives (rule matching, scoring) while keeping the learning loop isolated.

## Files

- `phase1_adapter.lua` - Pure functions calling Phase 1 decision primitives
- `ace_phase2_poc.lua` - Phase2Learner with isolated learning loop
- `rules_poc.lua` - 5 rules designed to trigger edge cases
- `demos/*.json` - 4 demo files testing edge cases
- `spec_*.lua` - Comprehensive test suites

## Running Tests

```bash
# Run all POC tests
busted poc/spec_*.lua

# Run specific test suite
busted poc/spec_phase1_adapter.lua
busted poc/spec_phase2_learner.lua
busted poc/spec_phase2_poc_integration.lua

# Run with verbose output
busted poc/ --verbose
```

## Test Coverage

- **Phase1Adapter (21 tests)** - NormalizeState, ComputeSalience, FindMatchingRules, ScoreActions, PredictAction
- **Rules (6 tests)** - Rule structure validation
- **Phase2Learner (7 tests)** - Learning algorithm validation
- **Integration (9 tests)** - End-to-end POC validation

**Total:** 43 tests

## Validated Invariants

✅ **No-competitor handling** - Increase-only updates when demonstrated action has no competitors
✅ **Epsilon-band competitor aggregation** - Correct flattening of competitor rules within epsilon
✅ **Margin saturation + clamping** - Bounded updates when `learning_rate * gap` exceeds `max_weight_delta`
✅ **Coverage failure** - Proper reporting when demonstrated action has no supporting rules
✅ **Determinism** - 10 runs with identical inputs produce identical outputs
✅ **Mass guards** - No divide-by-zero crashes
✅ **Canonical weights** - Read/write through `weights[key]` table

## Edge Cases Tested

1. **Demo 1 (poc_no_competitor_001.json)** - Math task with only RETRIEVE rule matching, no competitors
2. **Demo 2 (poc_epsilon_band_001.json)** - Factual task with two rules within epsilon=0.01 band
3. **Demo 3 (poc_margin_saturation_001.json)** - General task with large negative margin
4. **Demo 4 (poc_uncovered_001.json)** - VERIFY action with no supporting rules

## Next Steps

If POC validates successfully:
1. Integrate `LearnFromDemonstration` into full ACE (`dslua/agents/ace.lua`)
2. Add persistence (`ExportLearnedWeights`, `LoadWeightOverrides`)
3. Implement full demo loader with validation
4. Add train/validation split logic
5. Implement multi-epoch training with early stopping

## Tech Stack

- LuaJIT 2.1+
- busted (testing framework)
- dkjson (JSON encoding/decoding)

## Design Document

See `docs/plans/2026-01-31-ace-phase2-poc.md` for complete POC specification.
