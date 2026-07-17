(package "agnostic-llm" "0.4.0.0.20260717.0" "Agentic CLI integration.")

(website-url "https://github.com/rails-to-cosmos/agnostic-llm")
(keywords "convenience" "tools")

(package-file "agnostic-llm.el")

(script "test" "echo \"Error: no test specified\" && exit 1")

(source "gnu")
(source "melpa")
(source "rails-to-cosmos" "https://rails-to-cosmos.github.io/elpa/")

(depends-on "emacs" "28.1")
(depends-on "transient" "0.4.0")
(depends-on "vterm" "0.0.2")

(eask-defcommand test
  "Run the ERT suite in batch mode."
  (setq ert-batch-backtrace-right-margin 1200
        ert-batch-print-length 20
        ert-batch-print-level 10)
  (load "test/test-agnostic-llm.el")
  (ert-run-tests-batch-and-exit))
