set shell := ["cmd", "/c"]

# Default recipe
default:
    @just --list

# Run unit tests
unit:
    cls && zig build unit --summary all

# Build all examples
examples:
    cls && zig build examples

# Build and run a specific example
example name="simple":
    cls && zig build examples && zig-out\bin\{{name}}.exe

# Record input and launch visualizer (requires raylib)
input output="recordings\\input.json":
    just clean && cls && zig build input -- --output={{output}} && zig build visualizer -- {{output}}

# Build and run the visualizer with an existing recording (requires raylib)
visualizer recording:
    cls && zig build visualizer -- {{recording}}

# Run all tests
test:
    cls && zig build unit --summary all

# Build the project
build:
    cls && zig build

# Clean build artifacts
clean:
    cls
    if exist zig-out rd /s /q zig-out
    if exist .zig-cache rd /s /q .zig-cache
