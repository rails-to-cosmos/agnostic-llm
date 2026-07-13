;;; test-agnostic-llm.el --- Tests for agnostic-llm -*- lexical-binding: t; -*-

(require 'ert)
(require 'agnostic-llm)

;; ---------------------------------------------------------------------------
;; agnostic-llm--project-root
;; ---------------------------------------------------------------------------

(ert-deftest test-project-root-falls-back-to-dir ()
  "When no marker files exist, return the directory itself."
  (let ((dir (make-temp-file "agnostic-llm-test-" t)))
    (unwind-protect
        (let ((default-directory (file-name-as-directory dir)))
          (should (equal (agnostic-llm--project-root) (file-name-as-directory dir))))
      (delete-directory dir t))))

(ert-deftest test-project-root-finds-git ()
  "Should find root containing .git directory."
  (let ((dir (make-temp-file "agnostic-llm-test-" t)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name ".git" dir))
          (let ((sub (expand-file-name "src/" dir)))
            (make-directory sub t)
            (let ((default-directory sub))
              (should (equal (agnostic-llm--project-root) (file-name-as-directory dir))))))
      (delete-directory dir t))))

;; ---------------------------------------------------------------------------
;; agnostic-llm--write-context-file
;; ---------------------------------------------------------------------------

(ert-deftest test-write-context-file ()
  "Should write text to a temp file and return its path."
  (let ((file (agnostic-llm--write-context-file "hello world")))
    (unwind-protect
        (progn
          (should (file-exists-p file))
          (should (equal "hello world"
                         (with-temp-buffer
                           (insert-file-contents file)
                           (buffer-string)))))
      (ignore-errors (delete-file file)))))

;; ---------------------------------------------------------------------------
;; agnostic-llm--diff-added-lines
;; ---------------------------------------------------------------------------

(ert-deftest test-diff-added-lines-no-change ()
  "No changes should return empty list."
  (should (null (agnostic-llm--diff-added-lines "foo\nbar\n" "foo\nbar\n"))))

(ert-deftest test-diff-added-lines-detects-additions ()
  "Should detect added lines."
  (let ((lines (agnostic-llm--diff-added-lines "a\nb\n" "a\nx\nb\n")))
    (should (equal '(2) lines))))

;; ---------------------------------------------------------------------------
;; Model / effort resolution
;; ---------------------------------------------------------------------------

(defconst test-agnostic-llm--models
  '(("claude-fable-5"   . (:efforts ("default" "low" "medium" "high" "max" "ultracode")))
    ("claude-sonnet-5"  . (:efforts ("default" "low" "medium" "high" "max" "ultracode")))
    ("claude-opus-4-8"  . (:efforts ("default" "low" "medium" "high" "max" "ultracode")))
    ("claude-opus-4-7")
    ("claude-opus-4-6")
    ("claude-sonnet-4-6")
    ("claude-haiku-4-5"))
  "Fixture table mirroring the shipped `agnostic-llm-models' default.")

(ert-deftest test-model-split-alias ()
  "A bare alias splits to (FAMILY ()) with no version."
  (should (equal (agnostic-llm--model-split "opus") '("opus" ()))))

(ert-deftest test-model-split-versioned ()
  "A full name splits into family and up-to-two version integers."
  (should (equal (agnostic-llm--model-split "claude-opus-4-8") '("opus" (4 8)))))

(ert-deftest test-model-split-date-suffix ()
  "A trailing date component is ignored when splitting."
  (should (equal (agnostic-llm--model-split "claude-haiku-4-5-20251001")
                 '("haiku" (4 5)))))

(ert-deftest test-version< ()
  "Shorter version lists sort before longer ones sharing a prefix."
  (should (agnostic-llm--version< '(4) '(4 8)))
  (should (agnostic-llm--version< '(4 6) '(4 8)))
  (should-not (agnostic-llm--version< '(4 8) '(4 8)))
  (should-not (agnostic-llm--version< '(5) '(4 8))))

(ert-deftest test-effort-exact-name-has-ultracode ()
  "An exact name with declared efforts offers `ultracode'."
  (let ((agnostic-llm-models test-agnostic-llm--models))
    (should (member "ultracode"
                    (agnostic-llm-effort-choices-for-model "claude-opus-4-8")))))

(ert-deftest test-effort-per-model-gap ()
  "A model with no `:efforts' falls back to baseline, without `ultracode'."
  (let ((agnostic-llm-models test-agnostic-llm--models))
    (let ((choices (agnostic-llm-effort-choices-for-model "claude-opus-4-6")))
      (should-not (member "ultracode" choices))
      (should (equal choices agnostic-llm-effort-choices)))))

(ert-deftest test-effort-bare-alias-newest ()
  "A bare alias resolves to the newest family entry (here, with `ultracode')."
  (let ((agnostic-llm-models test-agnostic-llm--models))
    (should (member "ultracode"
                    (agnostic-llm-effort-choices-for-model "opus")))))

(ert-deftest test-effort-bare-alias-lower-versions-baseline ()
  "A bare alias whose family lacks declared efforts yields baseline only."
  (let ((agnostic-llm-models test-agnostic-llm--models))
    (should (equal (agnostic-llm-effort-choices-for-model "haiku")
                   agnostic-llm-effort-choices))))

(ert-deftest test-effort-date-suffix-resolves ()
  "A date-suffixed id resolves to its base entry (here, baseline efforts)."
  (let ((agnostic-llm-models test-agnostic-llm--models))
    (should (equal (agnostic-llm-effort-choices-for-model
                    "claude-haiku-4-5-20251001")
                   agnostic-llm-effort-choices))))

(ert-deftest test-effort-nil-model-is-first-entry ()
  "Nil model resolves to the first table entry (offers `ultracode' here)."
  (let ((agnostic-llm-models test-agnostic-llm--models))
    (should (member "ultracode"
                    (agnostic-llm-effort-choices-for-model nil)))))

(ert-deftest test-effort-unknown-model-baseline ()
  "An unknown model falls back to baseline efforts."
  (let ((agnostic-llm-models test-agnostic-llm--models))
    (should (equal (agnostic-llm-effort-choices-for-model "claude-mystery-9")
                   agnostic-llm-effort-choices))))

(ert-deftest test-model-choices-order ()
  "`agnostic-llm-model-choices' returns the table names in order."
  (let ((agnostic-llm-models test-agnostic-llm--models))
    (should (equal (agnostic-llm-model-choices)
                   '("claude-fable-5" "claude-sonnet-5" "claude-opus-4-8"
                     "claude-opus-4-7" "claude-opus-4-6" "claude-sonnet-4-6"
                     "claude-haiku-4-5")))))

(provide 'test-agnostic-llm)
;;; test-agnostic-llm.el ends here
