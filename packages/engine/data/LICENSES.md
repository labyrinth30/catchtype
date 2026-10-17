# Dictionary data — sources & licenses

Bundled lookup data used **only for "is this a word?" judgment**. Runtime
engine/CLI never touches the network; raw sources are fetched manually (or by
`packages/engine/scripts/build-data.ts` inputs) and only normalized TSVs are
committed.

| file | source | upstream license |
|---|---|---|
| `raw/en_raw.txt` | [first20hours/google-10000-english](https://github.com/first20hours/google-10000-english) `google-10000-english-no-swears.txt` | MIT (repository) |
| `raw/ko_raw.txt` | [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords) `content/2018/ko/ko_50k.txt` | MIT (repository); frequency data derived from OpenSubtitles 2018 corpus (CC BY-SA; see upstream README) |
| `en_words.txt` | normalized by `scripts/build-data.ts` (word + rank) | same as `en_raw.txt` |
| `ko_words.txt` | normalized by `scripts/build-data.ts` (word + frequency) | same as `ko_raw.txt` |

Normalization: EN keeps lowercase a–z words of length ≥ 2 (rank as weight);
KO keeps pure Hangul-syllable words (frequency as weight, deduped, highest kept).
