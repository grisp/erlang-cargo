erlang-cargo
============

![CI](https://github.com/rusterlium/erlang-cargo/workflows/CI/badge.svg)

Erlang library to interact with Rust's cargo.

## Development

Builds and EUnit work with stable Rust. Rust test execution uses libtest's
unstable JSON output and requires nightly:

```sh
rustup toolchain install nightly
rebar3 eunit
RUSTUP_TOOLCHAIN=nightly rebar3 ct
```
