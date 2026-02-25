use std::ffi::c_void;

type RbNoGvlFn = unsafe extern "C" fn(*mut c_void) -> *mut c_void;
type RbUnblockFn = unsafe extern "C" fn(*mut c_void);

unsafe extern "C" {
    fn rb_thread_call_without_gvl(
        func: Option<RbNoGvlFn>,
        data1: *mut c_void,
        ubf: Option<RbUnblockFn>,
        data2: *mut c_void,
    ) -> *mut c_void;
}

pub(crate) fn run_without_gvl<T>(task: &mut T, func: RbNoGvlFn) {
    // SAFETY:
    // - `task` remains alive during this call.
    // - `func` only works with Rust data and does not call Ruby APIs.
    unsafe {
        rb_thread_call_without_gvl(
            Some(func),
            (task as *mut T).cast::<c_void>(),
            None,
            std::ptr::null_mut(),
        );
    }
}
