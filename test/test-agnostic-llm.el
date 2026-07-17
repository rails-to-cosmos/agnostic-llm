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

(ert-deftest test-project-root-honors-override ()
  "A buffer-local `agnostic-llm--root-override' wins over marker search.
Even with a .git ancestor, the pinned directory is returned verbatim so a
session keeps its persistence anchored to the directory it launched in."
  (let ((dir (make-temp-file "agnostic-llm-test-" t)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name ".git" dir))
          (let ((sub (expand-file-name "src/deep/" dir)))
            (make-directory sub t)
            (with-temp-buffer
              (setq-local agnostic-llm--root-override sub)
              ;; default-directory is the git root; the override must still win.
              (let ((default-directory dir))
                (should (equal (agnostic-llm--project-root)
                               (file-name-as-directory (expand-file-name sub))))))))
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
    ("claude-opus-4-7"  . (:efforts ("default" "low" "medium" "high" "max")))
    ("claude-opus-4-6"  . (:efforts ("default" "low" "medium" "high" "max")))
    ("claude-sonnet-4-6" . (:efforts ("default" "low" "medium" "high" "max")))
    ("claude-haiku-4-5" . (:efforts ("default" "low" "medium" "high" "max"))))
  "Fixture table mirroring the shipped provider `:models' default.
Every entry declares its own `:efforts'; there is no fallback.")

(defmacro test-agnostic-llm--with-models (models &rest body)
  "Evaluate BODY with the active provider's catalog bound to MODELS.
Installs a throwaway provider carrying MODELS and the \"claude-\" model
prefix, so model/effort resolution reads MODELS instead of the shipped
default."
  (declare (indent 1))
  `(let ((agnostic-llm-provider 'test)
         (agnostic-llm-providers
          (list (cons 'test (list :model-prefix "claude-" :models ,models)))))
     ,@body))

(ert-deftest test-model-split-alias ()
  "A bare alias splits to (FAMILY ()) with no version."
  (should (equal (agnostic-llm--model-split "opus") '("opus" ()))))

(ert-deftest test-model-split-versioned ()
  "A full name splits into family and its version integers."
  (should (equal (agnostic-llm--model-split "claude-opus-4-8") '("opus" (4 8)))))

(ert-deftest test-model-split-date-suffix ()
  "A trailing date component is ignored when splitting.
The date drops for both two-integer versions (haiku-4-5) and
single-integer ones (sonnet-5), where it must not be mistaken for a
minor version."
  (should (equal (agnostic-llm--model-split "claude-haiku-4-5-20251001")
                 '("haiku" (4 5))))
  (should (equal (agnostic-llm--model-split "claude-sonnet-5-20260301")
                 '("sonnet" (5)))))

(ert-deftest test-version< ()
  "Shorter version lists sort before longer ones sharing a prefix."
  (should (agnostic-llm--version< '(4) '(4 8)))
  (should (agnostic-llm--version< '(4 6) '(4 8)))
  (should-not (agnostic-llm--version< '(4 8) '(4 8)))
  (should-not (agnostic-llm--version< '(5) '(4 8))))

(ert-deftest test-effort-exact-name-has-ultracode ()
  "An exact name with declared efforts offers `ultracode'."
  (test-agnostic-llm--with-models test-agnostic-llm--models
    (should (member "ultracode"
                    (agnostic-llm-effort-choices-for-model "claude-opus-4-8")))))

(ert-deftest test-effort-per-model-explicit ()
  "A model returns its own declared efforts; a non-ultracode model omits it."
  (test-agnostic-llm--with-models test-agnostic-llm--models
    (let ((choices (agnostic-llm-effort-choices-for-model "claude-opus-4-6")))
      (should-not (member "ultracode" choices))
      (should (equal choices '("default" "low" "medium" "high" "max"))))))

(ert-deftest test-effort-bare-alias-newest ()
  "A bare alias resolves to the newest family entry (here, with `ultracode')."
  (test-agnostic-llm--with-models test-agnostic-llm--models
    (should (member "ultracode"
                    (agnostic-llm-effort-choices-for-model "opus")))))

(ert-deftest test-effort-bare-alias-lower-versions-explicit ()
  "A bare alias resolves to its family's newest entry and its declared efforts."
  (test-agnostic-llm--with-models test-agnostic-llm--models
    (should (equal (agnostic-llm-effort-choices-for-model "haiku")
                   '("default" "low" "medium" "high" "max")))))

(ert-deftest test-effort-date-suffix-resolves ()
  "A date-suffixed id resolves to its base entry and its declared efforts."
  (test-agnostic-llm--with-models test-agnostic-llm--models
    (should (equal (agnostic-llm-effort-choices-for-model
                    "claude-haiku-4-5-20251001")
                   '("default" "low" "medium" "high" "max")))))

(ert-deftest test-effort-date-suffix-single-integer-version ()
  "A dated snapshot of a single-integer-version model keeps its efforts.
The date must not be read as a minor version, else \"claude-sonnet-5-20260301\"
would fail to match \"claude-sonnet-5\" and silently lose \"ultracode\"."
  (test-agnostic-llm--with-models test-agnostic-llm--models
    (should (member "ultracode"
                    (agnostic-llm-effort-choices-for-model
                     "claude-sonnet-5-20260301")))))

(ert-deftest test-effort-nil-model-is-first-entry ()
  "Nil model resolves to the first table entry (offers `ultracode' here)."
  (test-agnostic-llm--with-models test-agnostic-llm--models
    (should (member "ultracode"
                    (agnostic-llm-effort-choices-for-model nil)))))

(ert-deftest test-effort-unknown-model-nil ()
  "An unknown model has no declared efforts, so lookup returns nil."
  (test-agnostic-llm--with-models test-agnostic-llm--models
    (should-not (agnostic-llm-effort-choices-for-model "claude-mystery-9"))))

(ert-deftest test-effort-entry-without-efforts-nil ()
  "A known entry that declares no `:efforts' yields nil; there is no fallback."
  (test-agnostic-llm--with-models '(("claude-bare-1"))
    (should-not (agnostic-llm-effort-choices-for-model "claude-bare-1"))))

(ert-deftest test-model-choices-order ()
  "`agnostic-llm-model-choices' returns the table names in order."
  (test-agnostic-llm--with-models test-agnostic-llm--models
    (should (equal (agnostic-llm-model-choices)
                   '("claude-fable-5" "claude-sonnet-5" "claude-opus-4-8"
                     "claude-opus-4-7" "claude-opus-4-6" "claude-sonnet-4-6"
                     "claude-haiku-4-5")))))

;; ---------------------------------------------------------------------------
;; Provider abstraction
;; ---------------------------------------------------------------------------

(defmacro test-agnostic-llm--with-provider (plist &rest body)
  "Evaluate BODY with a throwaway active provider carrying PLIST."
  (declare (indent 1))
  `(let ((agnostic-llm-provider 'test)
         (agnostic-llm-providers (list (cons 'test ,plist))))
     ,@body))

(ert-deftest test-default-provider-is-claude ()
  "The shipped default provider drives the claude CLI."
  (should (eq agnostic-llm-provider 'claude))
  (should (equal (agnostic-llm--provider-get :executable) "claude")))

(ert-deftest test-provider-get-reads-active-entry ()
  "`agnostic-llm--provider-get' reads a field from the active provider."
  (test-agnostic-llm--with-provider '(:executable "codex" :print-flag "-q")
    (should (equal (agnostic-llm--provider-get :executable) "codex"))
    (should (equal (agnostic-llm--provider-get :print-flag) "-q"))))

(ert-deftest test-provider-unknown-signals ()
  "An unknown active provider signals an error."
  (let ((agnostic-llm-provider 'nope)
        (agnostic-llm-providers nil))
    (should-error (agnostic-llm--provider))))

(ert-deftest test-bubble-command-uses-provider-flags ()
  "The bubble argv is built from the provider's executable and flags."
  (test-agnostic-llm--with-provider
      (list :executable "codex" :session-id-flag "--sid"
            :model-flag "--model" :dangerous-flag "--yolo" :print-flag "-q")
    (let ((agnostic-llm--bubble-session-id "ABC")
          (agnostic-llm--bubble-model nil)
          (agnostic-llm--bubble-dangerous nil)
          (agnostic-llm-bubble-prompt-prefix ""))
      (should (equal (agnostic-llm--bubble-command "hi")
                     '("codex" "--sid" "ABC" "-q" "hi"))))))

(ert-deftest test-session-shell-command-uses-provider-executable ()
  "A fresh session's shell command is the provider executable plus set flags."
  (let ((dir (make-temp-file "agnostic-llm-test-" t)))
    (unwind-protect
        (test-agnostic-llm--with-provider
            (list :executable "codex" :continue-flag "-c"
                  :model-flag "--model" :effort-flag "--effort"
                  :dangerous-flag "--yolo"
                  :session-dir (file-name-as-directory dir)
                  :session-file-regexp "\\.jsonl\\'")
          (let ((default-directory (file-name-as-directory dir))
                (agnostic-llm-model nil)
                (agnostic-llm-effort nil)
                (agnostic-llm-dangerously-skip-permissions nil))
            (should (equal (agnostic-llm--session-shell-command dir) "codex"))
            (let ((agnostic-llm-model "m")
                  (agnostic-llm-dangerously-skip-permissions t))
              (should (equal (agnostic-llm--session-shell-command dir)
                             "codex --model m --yolo")))))
      (delete-directory dir t))))

(ert-deftest test-session-dir-encodes-under-provider-root ()
  "`agnostic-llm--session-dir' encodes the project dir under `:session-dir'."
  (test-agnostic-llm--with-provider '(:session-dir "/store/")
    (should (equal (agnostic-llm--session-dir "/home/u/proj")
                   (expand-file-name "-home-u-proj" "/store/")))))

;; ---------------------------------------------------------------------------
;; Session buffer naming
;; ---------------------------------------------------------------------------

(ert-deftest test-session-buffer-name-neutral-prefix ()
  "The session buffer name uses the backend-neutral prefix."
  (should (equal (agnostic-llm--session-buffer-name "foo")
                 "*llm:foo*")))

(ert-deftest test-buffer-p-recognizes-session-name ()
  "`agnostic-llm-buffer-p' recognizes a session-prefixed buffer.
A plain `*vterm:…*' buffer is not recognized."
  (let ((buf (get-buffer-create (agnostic-llm--session-buffer-name "foo"))))
    (unwind-protect
        (progn
          (should (equal (buffer-name buf) "*llm:foo*"))
          (should (agnostic-llm-buffer-p buf))
          (should-not (agnostic-llm-buffer-p (get-buffer-create "*vterm:foo*"))))
      (kill-buffer buf)
      (when (get-buffer "*vterm:foo*") (kill-buffer "*vterm:foo*")))))

(provide 'test-agnostic-llm)
;;; test-agnostic-llm.el ends here
