import importlib.util
import pathlib
import unittest
spec = importlib.util.spec_from_file_location('score', pathlib.Path(__file__).resolve().parents[2] / 'scripts/score-transcript.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
class ScoreTests(unittest.TestCase):
    def test_identical_normalized(self):
        self.assertEqual(module.score('Hello, WORLD! α.', 'hello world α')['wer'], 0)
    def test_substitution(self):
        self.assertEqual(module.score('one two three four', 'one two five four')['wer'], .25)
    def test_empty_reference(self):
        self.assertIsNone(module.score('', 'hello')['wer'])
    def test_insertions_and_deletions(self):
        self.assertEqual(module.score('one two', 'one two three')['insertions'], 1)
        self.assertEqual(module.score('one two', 'one')['deletions'], 1)
if __name__ == '__main__': unittest.main()
