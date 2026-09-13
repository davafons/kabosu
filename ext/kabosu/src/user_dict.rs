use std::fs::File;
use std::io::{BufWriter, Write};

use magnus::{Error, RArray, TryConvert, Value};
use memmap2::Mmap;
use sudachi::dic::binary_loader::LoadedDictionary;
use sudachi::dic::build::DictBuilder;

use crate::errors::{arg_error, sudachi_error};

/// Compiles user-dictionary CSV sources against one system dictionary, the
/// same way `sudachi ubuild` does. The result only loads alongside that exact
/// system dictionary: sudachi.rs 0.7 records which one it was built with.
pub(crate) fn build_user_dict(
    inputs: Value,
    system_dict: String,
    output: String,
    description: Option<String>,
) -> Result<(), Error> {
    let inputs: Vec<String> = match RArray::from_value(inputs) {
        Some(ary) => ary.to_vec()?,
        None => vec![String::try_convert(inputs)
            .map_err(|_| arg_error("inputs must be a String or an Array of String"))?],
    };
    if inputs.is_empty() {
        return Err(arg_error("inputs must name at least one CSV file"));
    }

    let system_file = File::open(&system_dict)
        .map_err(|e| sudachi_error(format!("cannot open system dictionary {system_dict}: {e}")))?;
    // SAFETY: read-only mapping that outlives every borrow made from it below.
    let system_data = unsafe { Mmap::map(&system_file) }.map_err(sudachi_error)?;
    let system = LoadedDictionary::load_system(&system_data).map_err(sudachi_error)?;

    let mut builder = DictBuilder::new_user(&system);
    builder.set_description(description.unwrap_or_default());
    for input in &inputs {
        builder
            .read_lexicon(std::path::Path::new(input))
            .map_err(sudachi_error)?;
    }
    builder.resolve().map_err(sudachi_error)?;

    let file =
        File::create(&output).map_err(|e| sudachi_error(format!("cannot create {output}: {e}")))?;
    let mut writer = BufWriter::new(file);
    builder.compile(&mut writer).map_err(sudachi_error)?;
    writer.flush().map_err(sudachi_error)?;
    Ok(())
}
