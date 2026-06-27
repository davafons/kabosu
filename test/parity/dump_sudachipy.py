"""Dump SudachiPy morpheme attributes as JSON Lines for the parity suite.

Usage: dump_sudachipy.py <corpus> <dict_path> <resource_dir> <config_path> <mode A|B|C>

Pointed at the SAME compiled dictionary, config, and resource directory that
kabosu uses, so that any value difference reflects a binding-layer or semantic
difference rather than a dictionary/config difference. Field names mirror the
kabosu/reference dumper where the concept is shared; SudachiPy's begin()/end()
are CHARACTER offsets (kabosu's begin_c/end_c), which the Ruby parity test
accounts for. WordInfo-derived fields (which SudachiPy exposes on a separate
object rather than on the morpheme) are included for non-OOV tokens.
"""

import json
import sys
import warnings

from sudachipy import Dictionary, SplitMode

MODES = {"A": SplitMode.A, "B": SplitMode.B, "C": SplitMode.C}


def corpus_lines(path):
    out = []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            out.append(line)
    return out


def main():
    corpus, dict_path, resource_dir, config_path, mode_name = sys.argv[1:6]
    mode = MODES[mode_name]

    d = Dictionary(config_path=config_path, resource_dir=resource_dir, dict=dict_path)
    tok = d.create(mode=mode)

    out = sys.stdout
    for line, text in enumerate(corpus_lines(corpus)):
        for index, m in enumerate(tok.tokenize(text, mode)):
            record = {
                "line": line,
                "index": index,
                "surface": m.surface(),
                "part_of_speech": list(m.part_of_speech()),
                "part_of_speech_id": m.part_of_speech_id(),
                "dictionary_form": m.dictionary_form(),
                "normalized_form": m.normalized_form(),
                "reading_form": m.reading_form(),
                "oov": m.is_oov(),
                "dictionary_id": m.dictionary_id(),
                "word_id": m.word_id(),
                # SudachiPy begin()/end() are character offsets.
                "begin_c": m.begin(),
                "end_c": m.end(),
                "synonym_group_ids": list(m.synonym_group_ids()),
            }
            if not m.is_oov():
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore")
                    wi = m.get_word_info()
                record.update(
                    head_word_length=wi.head_word_length,
                    dictionary_form_word_id=wi.dictionary_form_word_id,
                    a_unit_split=list(wi.a_unit_split),
                    b_unit_split=list(wi.b_unit_split),
                    word_structure=list(wi.word_structure),
                )
            out.write(json.dumps(record, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
