use magnus::{Error, Ruby};

pub(crate) fn arg_error(msg: impl Into<String>) -> Error {
    Error::new(Ruby::get().unwrap().exception_arg_error(), msg.into())
}

pub(crate) fn sudachi_error(e: impl std::fmt::Display) -> Error {
    Error::new(
        Ruby::get().unwrap().exception_runtime_error(),
        e.to_string(),
    )
}
