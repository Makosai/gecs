# GECS Changelog

## [5.0.0-rc4] - 2025-10-14 - Query Performance Optimization

### 🚀 Performance Improvements

#### Massive Query Cache Key Optimization

**85% faster cache key generation** leading to dramatic query performance improvements:

- **Cache key generation**: 283ms → 43ms (**85% faster**)
- **Query caching**: 500ms → 4.7ms (**99% faster**)
- **Query with all**: 13ms → 0.55ms (**96% faster**)
- **Query with any**: 27ms → 5.6ms (**79% faster**)
- **Complex queries**: Significantly improved scaling

**Technical Details:**

- Replaced expensive `str(comp)` fallbacks with direct `get_instance_id()` calls
- Eliminated conditional checks in cache key generation hot path
- Implemented polynomial rolling hash with XOR for collision resistance
- Used different prime multipliers (31, 37, 41) for component type separation

**Impact:**

- Query system now scales linearly instead of exponentially
- ECS performance optimized for large-scale applications (10,000+ entities)
- No performance regressions in any core ECS operations
- Cache effectiveness dramatically improved

See performance test results in `reports/perf/` for detailed metrics.

## [5.0.0] - 2025-01-XX - Relationship System Complete Overhaul

**GECS v5.0.0 is a major release focusing on API simplification, proper ECS architecture enforcement, and relationship system improvements.**

### 📦 What's in This Release

This release includes **3 breaking changes** and several new features:

1. **Entity.on_update() removed** - Enforces proper ECS separation of concerns
2. **System.process_all() no longer returns bool** - Simplified internal API
3. **Relationship system overhaul** - Removed weak/strong matching in favor of component queries
4. **Target component queries** - Query both relation and target entity properties
5. **Limited relationship removal** - Remove specific number of relationships
6. **Topological sort fix** - System dependencies now execute in correct order
7. **Performance improvements** - 2-7% faster system processing

### ⚠️ BREAKING CHANGES

#### Entity.on_update() Lifecycle Method Removed

The `on_update(delta)` lifecycle method has been removed from the Entity class:

- **`on_update(delta)` method removed** - This lifecycle hook is no longer called
- **Use Systems instead** - Entity logic should be handled by Systems, not in Entity methods
- **Cleaner separation of concerns** - Entities are data containers, Systems contain logic

**Migration:**

| Old (v4.x)                                             | New (v5.0)                                  |
| ------------------------------------------------------ | ------------------------------------------- |
| Override `on_update(delta)` in Entity class           | Create a System that processes the entity   |
| `entity.on_update(delta)` called every frame          | System.process(entity, delta)              |

**Example Migration:**

```gdscript
# ❌ Old (v4.x) - Logic in Entity
class_name MyEntity extends Entity:
    func on_update(delta: float):
        # Entity logic here
        position += velocity * delta

# ✅ New (v5.0) - Logic in System
class_name MySystem extends System:
    func query():
        return q.with_all([C_Transform, C_Velocity])

    func process(entity: Entity, delta: float):
        var transform = entity.get_component(C_Transform)
        var velocity = entity.get_component(C_Velocity)
        transform.position += velocity.direction * velocity.speed * delta
```

**Why this change?**
This enforces proper ECS architecture where Entities are pure data containers and all logic lives in Systems. This makes code more modular, testable, and performant.

#### System.process_all() and System._process_parallel() No Longer Return Booleans

The `process_all()` and `_process_parallel()` methods now return `void` instead of `bool`:

- **`did_run` variable removed** - Internal tracking variable was never used
- **Return type changed from `bool` to `void`** - Return values were never checked or used
- **No functional impact** - These were internal implementation details

**Migration:**

| Old (v4.x)                                             | New (v5.0)                                  |
| ------------------------------------------------------ | ------------------------------------------- |
| `var result = system.process_all(entities, delta)`    | `system.process_all(entities, delta)`       |
| Override `process_all()` returning `bool`             | Override `process_all()` returning `void`   |

**Why this change?**
The boolean return values were historical artifacts that were never actually used anywhere in the codebase. Removing them simplifies the API and makes the code cleaner.

#### Removed Weak/Strong Matching System

The weak/strong matching system has been completely replaced with a simpler, more intuitive approach:

- **`weak` parameter removed** from all relationship methods
- **`Component.equals()` method removed** - use component queries instead
- **Type matching is now the default** - matches by component type only
- **Component queries for property matching** - use dictionaries for property-based filtering

**Migration:**

| Old (v4.x)                                                                | New (v5.0)                                                                           |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `entity.has_relationship(Relationship.new(C_Eats.new(5), target), false)` | `entity.has_relationship(Relationship.new({C_Eats: {'value': {"_eq": 5}}}, target))` |
| `entity.has_relationship(Relationship.new(C_Eats.new(), target), true)`   | `entity.has_relationship(Relationship.new(C_Eats.new(), target))`                    |
| `entity.get_relationship(rel, true, true)`                                | `entity.get_relationship(rel)`                                                       |
| `entity.get_relationships(rel, true)`                                     | `entity.get_relationships(rel)`                                                      |
| Override `equals()` in component                                          | Use component queries: `{C_Type: {'prop': {"_eq": value}}}`                          |

#### Component Query Improvements

- **Target component queries added** - Query both relation AND target component properties
- **Cannot add query relationships to entities** - Queries are for matching only, not storage
- **Fixed bug with falsy values** - Component queries now correctly handle `0`, `false`, etc.

### ✨ New Features

#### Simplified Relationship Matching

```gdscript
# Type matching (default) - matches by component type
entity.has_relationship(Relationship.new(C_Damage.new(), target))

# Component query - matches by property criteria
entity.has_relationship(Relationship.new({C_Damage: {'amount': {"_gte": 50}}}, target))

# Query both relation AND target
var strong_buffs = ECS.world.query.with_relationship([
    Relationship.new(
        {C_Buff: {'duration': {"_gt": 10}}},
        {C_Player: {'level': {"_gte": 5}}}
    )
]).execute()
```

#### Target Component Queries (NEW!)

```gdscript
# Query relationships by target component properties
var high_hp_targets = ECS.world.query.with_relationship([
    Relationship.new(C_Targeting.new(), {C_Health: {'hp': {"_gte": 100}}})
]).execute()

# Mix relation and target queries
var critical_effects = ECS.world.query.with_relationship([
    Relationship.new(
        {C_Damage: {'type': {"_in": ["fire", "ice"]}}},
        {C_Entity: {'level': {"_gte": 10}}}
    )
]).execute()
```

#### Limited Relationship Removal

```gdscript
# Remove specific number of relationships
entity.remove_relationship(Relationship.new(C_Damage.new(), null), 1)  # Remove 1 damage
entity.remove_relationship(Relationship.new(C_Buff.new(), null), 3)    # Remove up to 3 buffs

# Combine with component queries
entity.remove_relationship(
    Relationship.new({C_Damage: {'amount': {"_gt": 20}}}, null),
    2  # Remove up to 2 high-damage effects
)
```

### 🚨 Migration Guide

#### 1. Remove `weak` Parameters

```gdscript
# ❌ Old (v4.x)
entity.has_relationship(rel, true)
entity.get_relationship(rel, true, true)
entity.get_relationships(rel, false)

# ✅ New (v5.0)
entity.has_relationship(rel)
entity.get_relationship(rel)
entity.get_relationships(rel)
```

#### 2. Replace Strong Matching with Component Queries

```gdscript
# ❌ Old (v4.x) - strong matching for exact values
entity.has_relationship(Relationship.new(C_Eats.new(5), target), false)

# ✅ New (v5.0) - component query
entity.has_relationship(Relationship.new({C_Eats: {'value': {"_eq": 5}}}, target))
```

#### 3. Remove `equals()` Overrides

```gdscript
# ❌ Old (v4.x) - custom equals() method
class_name C_Damage extends Component:
    @export var amount: int = 0

    func equals(other: Component) -> bool:
        return amount == other.amount

# ✅ New (v5.0) - use component queries
# No equals() method needed!
# Query by property: {C_Damage: {'amount': {"_eq": 50}}}
```

#### 4. Check any deps function and sorting order

Topological sort was broken in previous versions. It is now fixed and as a result some systems may now be running in the correct order defined in the deps
but it may end up to be the wrong order for your game code. Check these depenencies by doing: `print(ECS.world.systems_by_group)` this will show you the sorted
systems and how they are running. Do a comparison between this version and the previous versions of GECS.

### 🧪 Test Suite Improvements

#### Performance Test Cleanup

- **Eliminated orphan nodes** - Refactored all performance tests to use `scene_runner` pattern
- **Proper lifecycle management** - Tests now use `auto_free()` and `world.purge()` for cleanup
- **Consistent test structure** - All performance tests follow same pattern as core tests
- **Zero orphan nodes** - Performance tests now maintain clean test environment

**Files Updated:**

- `addons/gecs/tests/performance/performance_test_base.gd` - Uses scene_runner for proper test setup
- `addons/gecs/tests/performance/performance_test_entities.gd` - Refactored to use auto_free pattern
- `addons/gecs/tests/performance/performance_test_components.gd` - Simplified cleanup using world.purge
- `addons/gecs/tests/performance/performance_test_queries.gd` - Removed manual cleanup code
- `addons/gecs/tests/performance/performance_test_systems.gd` - Uses scene_runner for world management
- `addons/gecs/tests/performance/performance_test_integration.gd` - Consistent with core test patterns
- `addons/gecs/tests/performance/performance_test_system_process.gd` - Proper node lifecycle management

### 📊 Performance Improvements

All changes maintain or improve performance:

- **System processing**: 2-7% faster across all benchmarks
- **system_processing** (10k): 25.256ms → 24.183ms (**4.2% faster**)
- **multiple_systems** (10k): 136.064ms → 132.285ms (**2.8% faster**)
- **system_no_matches** (10k): 0.081ms → 0.075ms (**7.4% faster**)

Removing unused boolean returns and `did_run` tracking reduced conditional logic and CPU overhead.

### 📦 Files Changed in This Release

**Core Framework Changes:**
- `addons/gecs/ecs/entity.gd` - **BREAKING**: Removed `on_update()` lifecycle method and weak parameters from relationship methods
- `addons/gecs/ecs/system.gd` - **BREAKING**: `process_all()` and `_process_parallel()` now return `void` instead of `bool`
- `addons/gecs/ecs/relationship.gd` - **BREAKING**: Removed weak parameter, added target_query support
- `addons/gecs/ecs/component.gd` - **BREAKING**: Removed `equals()` method
- `addons/gecs/ecs/world.gd` - System dependency topological sort fixes
- `addons/gecs/ecs/ecs.gd` - Updated for new system processing

**Library Updates:**
- `addons/gecs/lib/component_query_matcher.gd` - **FIXED**: Properly handle falsy values (0, false, etc.)

**Documentation Updates:**
- `addons/gecs/docs/CORE_CONCEPTS.md` - Updated entity lifecycle and system examples
- `addons/gecs/docs/RELATIONSHIPS.md` - Complete rewrite for new relationship system
- `addons/gecs/docs/CLAUDE.md` - Updated with new relationship patterns
- `CHANGELOG.md` - Comprehensive v5.0.0 documentation
- `README.md` - Updated for v5.0.0 release

**Test Updates:**
- `addons/gecs/tests/core/test_relationships.gd` - Updated all tests to new API
- `addons/gecs/tests/systems/s_performance_test.gd` - Updated for new system signatures
- `addons/gecs/tests/systems/s_noop.gd` - New test helper system
- `addons/gecs/tests/performance/test_hotpath_breakdown.gd` - New performance test

**Example Updates:**
- `example/main.gd` - Updated to use v5.0.0 API
- `example/systems/s_velocity.gd` - Updated system implementation
- `example/systems/s_random_velocity.gd` - Updated system implementation

---

## [3.8.0] - 2024-XX-XX - Performance Boost & Documentation Overhaul

## 🎯 Major Improvements

### ⚡ Performance Optimizations

- **1.58x Query Performance Boost** - Implemented QueryBuilder pooling and world-level query caching
- **Fixed Component Replacement Bug** - Entities no longer processed twice when components are replaced
- **Array Operations Performance Revolution** - 4.6x faster intersection, 2.6x faster difference, 1.8x faster union operations
- **Memory Leak Prevention** - Better resource management and cleanup

### 📚 Complete Documentation Restructure

- **User-Friendly Learning Path** - Progressive guides from 5-minute tutorial to advanced optimization
- **Comprehensive Guides** - New Getting Started, Best Practices, Performance, and Troubleshooting guides
- **Addon-Centric Documentation** - All docs now ship with the addon for better distribution
- **Consistent Naming Conventions** - Standardized C*, s*, e*, o* prefixes throughout
- **Community Integration** - Discord links throughout for support

### 🧪 Enhanced Testing Framework

- **Performance Test Suite** - Comprehensive benchmarking for all ECS operations
- **Regression Detection** - Automated performance threshold monitoring
- **Better Test Organization** - Restructured tests into logical groups (core/, performance/)

## 🔧 Technical Changes

### Core Framework

- **QueryBuilder Pooling** - Reduced object creation overhead
- **World-Level Query Caching** - Hash-based caching with automatic invalidation
- **Component Replacement Fix** - Proper removal before replacement in entity.gd:97-111
- **Array Performance Revolution** - Algorithmic improvements from O(n²) to O(n) complexity using dictionary lookups

### Documentation Structure

- **Root README.md** - Clean overview pointing to addon documentation
- **addons/gecs/README.md** - Complete documentation index for distribution
- **addons/gecs/docs/** - All user guides properly organized
- **Progressive Learning Path** - 5min → 20min → 60min guide progression

### Testing & Quality

- **Performance Baselines** - Established benchmarks for regression detection
- **Comprehensive Coverage** - Entity, Component, Query, System, and Integration tests
- **Cross-Platform Compatibility** - Improved test reliability

## 📈 Performance Metrics

### Array Operations Benchmarks

- **Intersection Operations**: 4.6x faster (0.888ms → 0.194ms)
- **Difference Operations**: 2.6x faster (0.361ms → 0.141ms)
- **Union Operations**: 1.8x faster (0.372ms → 0.209ms)
- **No Overlap Scenarios**: 4.2x faster (0.629ms → 0.149ms)

### Algorithmic Improvements

- **O(n²) → O(n) Complexity**: Replaced Array.has() with Dictionary lookups
- **Smart Size Optimization**: Intersect operations use smaller array for lookup table
- **Uniqueness Tracking**: Union operations prevent duplicates with dictionary-based deduplication
- **Consistent Optimization Pattern**: All array operations use same high-performance approach

### Framework Performance

- **Query Caching**: 1.58x speedup for repeated queries
- **Component Operations**: Reduced double-processing bugs
- **Memory Usage**: Better cleanup and resource management
- **Test Suite**: Comprehensive benchmarking with automatic thresholds

## 🎮 For Game Developers

- **Dramatically Faster Games** - Up to 4.6x performance improvement in entity filtering and complex queries
- **Better Documentation** - Clear learning path from beginner to advanced
- **Consistent Patterns** - Standardized naming and organization conventions
- **Community Support** - Discord integration for help and discussions

## 🔄 Migration Notes

This is a **backward-compatible** update. No breaking changes to the API.

- Existing projects will automatically benefit from performance improvements
- Documentation has been reorganized but all links remain functional
- Test structure improved but does not affect game development

## 🌟 Community

- **Discord**: [Join our community](https://discord.gg/eB43XU2tmn)
- **Documentation**: [Complete guides](addons/gecs/README.md)
- **Issues**: [Report bugs or request features](https://github.com/csprance/gecs/issues)

---

**Full Changelog**: [v3.7.0...v3.8.0](https://github.com/csprance/gecs/compare/v3.7.0...v3.8.0)

The v3.8.0 version reflects a significant minor release with substantial improvements to performance, documentation, and testing while maintaining full backward compatibility with the existing v3.x API.
