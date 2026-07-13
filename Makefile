EMACS   ?= emacs
PACKAGE := agnostic-llm.el

.PHONY: all check lint checkdoc compile test clean help

all: lint compile test

check: all

help:
	@echo "Targets:"
	@echo "  lint     Run package-lint + checkdoc (auto-installs package-lint from MELPA)"
	@echo "  checkdoc Run checkdoc over the package; fail on any finding"
	@echo "  compile  Byte-compile with warnings as errors"
	@echo "  test     Run the ERT suite in batch mode"
	@echo "  clean    Remove .elc files"
	@echo "  all      lint + compile + test (mirrors CI; alias: check)"
	@echo "  help     This message"
	@echo ""
	@echo "compile and test run package-initialize so installed deps (transient,"
	@echo "vterm) are on load-path.  Override Emacs with EMACS=...; e.g."
	@echo "make compile EMACS=/usr/bin/emacs29"

lint: checkdoc
	$(EMACS) --batch \
	  --eval "(require 'package)" \
	  --eval "(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\"))" \
	  --eval "(package-initialize)" \
	  --eval "(unless (package-installed-p 'package-lint) (package-refresh-contents) (package-install 'package-lint))" \
	  -l package-lint \
	  -f package-lint-batch-and-exit \
	  $(PACKAGE)

checkdoc:
	$(EMACS) --batch \
	  --eval "(require 'checkdoc)" \
	  --eval "(setq checkdoc-autofix-flag 'never)" \
	  --eval "(checkdoc-file \"$(PACKAGE)\")" \
	  --eval "(when (get-buffer \"*Warnings*\") (kill-emacs 1))"

compile: clean
	$(EMACS) --batch \
	  --eval "(require 'package)" \
	  --eval "(package-initialize)" \
	  --eval "(setq byte-compile-error-on-warn t)" \
	  -L . \
	  -f batch-byte-compile $(PACKAGE)

test:
	$(EMACS) --batch \
	  --eval "(require 'package)" \
	  --eval "(package-initialize)" \
	  -L . -L test \
	  -l test/test-agnostic-llm.el \
	  -f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc

