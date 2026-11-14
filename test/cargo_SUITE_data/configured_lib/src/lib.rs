#[cfg(feature = "default_marker")]
compile_error!("default features must be disabled");
#[cfg(not(feature = "selected"))]
compile_error!("selected feature must be enabled");
#[cfg(not(cargo_configured))]
compile_error!("configured rustflags must reach rustc");

pub fn configured_value() -> &'static str {
    env!("CARGO_TEST_VALUE")
}
