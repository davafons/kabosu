"""Dump SudachiPy morpheme attributes as JSON Lines for the parity suite.

Usage: dump_sudachipy.py <corpus> <dict_path> <resource_dir> <config_path> <mode A|B|C>

Pointed at the SAME compiled dictionary, config, and resource directory that
kabosu uses, so that any value difference reflects a binding-layer or semantic
difference rather than a dictionary/config difference. Field names mirror the
kabosu/reference dumper where the concept is shared; SudachiPy's begin()/end()
are CHARACTER offsets (kabosu's begin_c/end_c), which the Ruby parity test
accounts for. SudachiPy 0.7 removed WordInfo, so word-info fields
(head_word_length, splits, ...) are only checked by the conformance suite.
"""

import json
import sys

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
    tok = d.tokenizer(mode=mode)

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
            out.write(json.dumps(record, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
