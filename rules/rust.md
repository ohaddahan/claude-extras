# Rust Policy

## Structs

- All fields are public
- All methods are public
- Struct itself is public

## Functions

- All functions are public
- If there is more than one argument of the same type, use an input struct
- If there are more than three arguments, use an input struct
- Always fully destruct the input struct, to ensure we always use all of the fields inside the method

## Format

- Use `cargo fmt`

## Lint

- Use `cargo clippy`

## Helpers

- Make folders per topic
- Prefer using a struct with static methods
- The helper name is helpful for namespacing for example CircuitHelpers

