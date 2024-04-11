;;; test-cern-root-mode.el --- Test suite for cern-root-mode.el          -*- lexical-binding: t; -*-

;; Copyright (C) 2022  Jay Morgan

;; Author: Jay Morgan <jay@morganwastaken.com>

(require 'cern-root-mode)

;; helper functions
(defmacro with-cern-root-repl (&rest body)
  `(progn
     (cern-root-run)
     ,@body
     (let ((kill-buffer-query-functions nil))
       (kill-buffer cern-root-buffer-name))))

;; example test files
(defconst test-file-1
  "#include <cstdio>
int test() {
    printf(\"This is a test\");
    return 0;
}")

(defconst test-file-2
  "#include <string>
#include <cstdio>

template<typename T>
T add(T a, T b) {
    return a + b;
}

/* 
 * this is a function
 * @param : no param
 * @return : int
 */
int test() {
    // run the test
    return add(1, 2);
}")

(defconst test-file-3
  "#include <cstdio>

struct MyFairClass {
    MyFairClass(const char* name) : name {name} {};
    void print_my_name() {
        printf(\"My Fair %s\\n\", this->name);
    }
    private:
    const char* name;
};

void test() {
    MyFairClass m{\"Lady\"};
    m.print_my_name();
}")

(defconst test-file-4
  "template      <typename F>
struct Person {
  F age;
};

double test() {
    Person<double> p = { 54.4 };
    return p.age;
}")

(defconst test-file-5
  "float test(void)
{
  float val = 20.; // this is a test
  /*
   * This is a multiline comment
   */
  return exp(-val);
  /*
   * this is another comment.
   */ 
}")

(defconst test-file-6
  ".rawInput
std::vector<std::vector<std::string>> test(void)
{
  // function that returns a vector of vector
  // of strings.
  return { {\"this\", \"is\", \"a\", \"test\"} };
}
.rawInput")

;;; begin tests

(ert-deftest cern-root-test-push-new ()
  "Tests the functionality of push-new in root.el"
  (should (equal (cern-root--push-new "a" (list "b" "c")) (list "a" "b" "c"))))

(ert-deftest cern-root-test-pluck-item ()
  "Tests the functionality of plucking an item from a list as defined in root.el"
  (should (equal (cern-root--pluck-item 'a '((a . b))) 'b))
  (should (equal (cern-root--pluck-item 'a '((b . c))) nil))
  (should (equal (cern-root--pluck-item "a" '(("a" . 3))) 3))
  (should (equal (cern-root--pluck-item :a '((:a . b))) 'b))
  (should (equal (cern-root--pluck-item 'a '((a . b) (a . c))) 'b)))

(ert-deftest cern-root-test-make-earmuff ()
  "Tests that a string can be given earmuffs, i.e. name -> *name*"
  (should (equal (cern-root--make-earmuff "name") "*name*"))
  (should (equal (cern-root--make-earmuff "*name*") "*name*"))
  (should (equal (cern-root--make-earmuff "*name") "**name*"))
  (should (equal (cern-root--make-earmuff "") ""))
  (should (equal (cern-root--make-earmuff "a") "*a*")))

(ert-deftest cern-root-test-make-no-earmuff ()
  "Tests that earmuffs can be removed from strings"
  (should (equal (cern-root--make-no-earmuff "*name*") "name"))
  (should (equal (cern-root--make-no-earmuff "name") "name"))
  (should (equal (cern-root--make-no-earmuff "") ""))
  (should (equal (cern-root--make-no-earmuff "a") "a")))

(defmacro do-test-file (test-file expected)
  `(with-cern-root-repl
    (cern-root-eval-string ,test-file)
    (cern-root-eval-string "test()")
    (sleep-for 0.05)
    (let ((result (cern-root--get-last-output)))
      (should (equal result ,expected)))))

(ert-deftest cern-root-test-root-file-1 ()
  "Tests that test-file-1 can be sent to the REPL and the correct result is returned"
  (do-test-file test-file-1 "This is a test(int) 0\n"))

(ert-deftest cern-root-test-root-file-2 ()
  "Tests that test-file-2 can be send to the ROOT REPL and the correct result is returned."
  (do-test-file test-file-2 "(int) 3\n"))

(ert-deftest cern-root-test-root-file-3 ()
  "Tests that test-file-3 can be sent to the REPL and the correct result is returned."
  (do-test-file test-file-3 "My Fair Lady\n"))

(ert-deftest cern-root-test-root-file-4 ()
  "Tests that a templated struct can be parsed."
  (do-test-file test-file-4 "(double) 54.400000\n"))

(ert-deftest cern-root-test-root-file-5 ()
  "Tests that a different curly-braces style and comments can be parsed."
  (do-test-file test-file-5 "(float) 2.06115e-09f\n"))

(ert-deftest cern-root-test-root-file-6 ()
  "Tests that functions with <> in the returns are parsed correctly."
  (do-test-file test-file-6 ""))
