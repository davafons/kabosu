use magnus::{Error, RArray, Ruby};
use std::sync::Arc;
use sudachi::dic::dictionary::JapaneseDictionary;

use crate::morpheme::{rb_morpheme_from_data, MorphemeData};

/// Group raw `MorphemeData` into jpdb-style chips.
pub(crate) fn group_morphemes_rust(
    morphemes: &[MorphemeData],
    dict: &Arc<JapaneseDictionary>,
    debug: bool,
) -> Result<RArray, Error> {
    let ruby = Ruby::get().unwrap();
    let mut groups: Vec<Vec<MorphemeData>> = Vec::with_capacity(morphemes.len());

    for m in morphemes {
        if let Some(last_group) = groups.last_mut() {
            let head = &last_group[0];
            let prev = last_group.last().unwrap();
            if is_content_word(head.pos_id, dict) && extends_group(m, prev, dict) {
                last_group.push(m.clone());
                continue;
            }
        }
        groups.push(vec![m.clone()]);
    }

    let result = ruby.ary_new();
    for group in groups {
        let group_ary = ruby.ary_new();
        for data in group {
            group_ary.push(rb_morpheme_from_data(data, dict.clone(), debug))?;
        }
        result.push(group_ary)?;
    }
    Ok(result)
}

// POS helpers

fn is_content_word(pos_id: u16, dict: &JapaneseDictionary) -> bool {
    !matches!(
        dict.grammar()
            .pos_components(pos_id)
            .first()
            .map(|s| s.as_str()),
        Some("助詞") | Some("助動詞") | Some("補助記号") | Some("記号") | Some("空白")
    )
}

fn extends_group(m: &MorphemeData, prev: &MorphemeData, dict: &JapaneseDictionary) -> bool {
    let comps = dict.grammar().pos_components(m.pos_id);
    let pos0 = comps.first().map(|s| s.as_str());
    let pos1 = comps.get(1).map(|s| s.as_str());

    match pos0 {
        Some("助動詞") => true,
        Some("助詞") => {
            if is_clause_boundary(m.surface.as_str(), m.pos_id, dict) {
                return false;
            }
            if pos1 == Some("接続助詞") {
                return true;
            }
            // 副助詞 clings to preceding verb/adjective (e.g. たり/だり)
            if pos1 == Some("副助詞") && is_verb_adj_adv(prev.pos_id, dict) {
                return true;
            }
            false
        }
        Some("動詞") => {
            if pos1 != Some("非自立可能") {
                return false;
            }
            // te-form auxiliary chain: て/で + いる/ある/くる/etc.
            let prev_pos0 = dict
                .grammar()
                .pos_components(prev.pos_id)
                .first()
                .map(|s| s.as_str());
            if prev_pos0 == Some("助詞") && (prev.surface == "て" || prev.surface == "で") {
                return true;
            }
            // compound verb (V+V) intentionally skipped — caller handles DB lookup
            false
        }
        _ => false,
    }
}

fn is_clause_boundary(surface: &str, pos_id: u16, dict: &JapaneseDictionary) -> bool {
    let comps = dict.grammar().pos_components(pos_id);
    let pos0 = comps.first().map(|s| s.as_str());
    let pos1 = comps.get(1).map(|s| s.as_str());

    if pos0 == Some("助詞") {
        if is_clause_boundary_particle(surface) {
            return true;
        }
        // contrastive が (接続助詞) is a boundary, unlike subject が (格助詞)
        if pos1 == Some("接続助詞") && surface == "が" {
            return true;
        }
    }
    false
}

fn is_clause_boundary_particle(surface: &str) -> bool {
    matches!(
        surface,
        "ながら"
            | "たら"
            | "ば"
            | "と"
            | "のに"
            | "から"
            | "ので"
            | "けれど"
            | "けど"
            | "つつ"
            | "なり"
            | "や"
            | "か"
            | "かどうか"
            | "とも"
    )
}

fn is_verb_adj_adv(pos_id: u16, dict: &JapaneseDictionary) -> bool {
    matches!(
        dict.grammar()
            .pos_components(pos_id)
            .first()
            .map(|s| s.as_str()),
        Some("動詞") | Some("形容詞") | Some("形状詞")
    )
}
