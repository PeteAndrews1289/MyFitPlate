import unittest

from ui_launch_retries import classify_failures


class LaunchRetryTests(unittest.TestCase):
    first = "DiaryTests/testSave()"
    second = "ProgramTests/testAdvance()"
    launch = "Failed to get background assertion for target app with pid 246: Timed out while acquiring background assertion."

    def classify(self, failures, count):
        return classify_failures({
            "result": "Failed",
            "failedTests": count,
            "testFailures": [{"testIdentifierString": name, "failureText": message} for name, message in failures],
        })

    def test_launch_failure_can_be_retried_even_if_another_test_failed(self):
        retry, blocking = self.classify([(self.first, self.launch), (self.second, "XCTAssertEqual failed")], 2)
        self.assertEqual(retry, [self.first])
        self.assertEqual(blocking, [self.second])

    def test_a_method_with_a_real_failure_is_never_eligible(self):
        retry, blocking = self.classify([(self.first, self.launch), (self.first, "XCTAssertEqual failed")], 1)
        self.assertEqual(retry, [])
        self.assertEqual(blocking, [self.first])

    def test_only_a_complete_set_of_launch_failures_can_clear_the_original_job(self):
        repeated = [(self.first, self.launch), (self.first, self.launch)]
        self.assertEqual(self.classify(repeated, 1), ([self.first], []))
        for failures, count in [(repeated, 2), (repeated + [("", "Runner terminated")], 1), ([], 0)]:
            with self.subTest(failures=failures, count=count):
                self.assertTrue(self.classify(failures, count)[1])

    def test_other_timeouts_stay_blocking(self):
        self.assertEqual(self.classify([(self.first, "Timed out waiting for a saved workout")], 1), ([], [self.first]))
