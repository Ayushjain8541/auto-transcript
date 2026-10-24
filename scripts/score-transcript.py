#!/usr/bin/env python3
"""Word error rate with NFKC, case folding, and punctuation normalization."""
import argparse
import json
import pathlib
import unicodedata

def words(text):
    normalized = unicodedata.normalize('NFKC', text).casefold()
    return ''.join(' ' if unicodedata.category(c).startswith('P') else c for c in normalized).split()

def score(reference, hypothesis):
    ref, hyp = words(reference), words(hypothesis)
    # Each entry is (distance, substitutions, deletions, insertions).
    previous = [(i, 0, 0, i) for i in range(len(hyp) + 1)]
    for row, expected in enumerate(ref, 1):
        current = [(row, 0, row, 0)]
        for column, actual in enumerate(hyp, 1):
            if expected == actual:
                current.append(previous[column - 1])
            else:
                diagonal, above, left = previous[column - 1], previous[column], current[-1]
                candidates = [(diagonal[0]+1, diagonal[1]+1, diagonal[2], diagonal[3]),
                              (above[0]+1, above[1], above[2]+1, above[3]),
                              (left[0]+1, left[1], left[2], left[3]+1)]
                current.append(min(candidates, key=lambda entry: entry[0]))
        previous = current
    edits, substitutions, deletions, insertions = previous[-1]
    return dict(reference_words=len(ref), substitutions=substitutions, deletions=deletions,
                insertions=insertions, wer=edits/len(ref) if ref else None)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=pathlib.Path)
    parser.add_argument('hypothesis', type=pathlib.Path)
    args = parser.parse_args()
    print(json.dumps(score(args.reference.read_text(), args.hypothesis.read_text()), indent=2))
if __name__ == '__main__': main()
