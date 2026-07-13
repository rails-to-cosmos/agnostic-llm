EMACS   ?= emacs
PACKAGE := agnostic-llm.el

.PHONY: all check lint checkdoc compile test clean help major minor patch

all: lint compile test

check: all

help:
	@echo "Targets:"
	@echo "  lint     Run package-lint + checkdoc (auto-installs package-lint from MELPA)"
	@echo "  checkdoc Run checkdoc over the package; fail on any finding"
	@echo "  compile  Byte-compile with warnings as errors"
	@echo "  test     Run the ERT suite in batch mode"
	@echo "  clean    Remove .elc files"
	@echo "  major    Bump the major part of Package-Version (X.y.z -> X+1.0.0)"
	@echo "  minor    Bump the minor part of Package-Version (x.Y.z -> x.Y+1.0)"
	@echo "  patch    Bump the patch part of Package-Version (x.y.Z -> x.y.Z+1)"
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

major minor patch:
	@old=$$(sed -n 's/^;; Package-Version: *//p' $(PACKAGE)); \
	[ -n "$$old" ] || { echo "No Package-Version header in $(PACKAGE)" >&2; exit 1; }; \
	new=$$(echo "$$old" | awk -F. -v part=$@ '{ \
	  if (part == "major")      { $$1++; $$2 = 0; $$3 = 0 } \
	  else if (part == "minor") { $$2++; $$3 = 0 } \
	  else                      { $$3++ }; \
	  printf "%d.%d.%d", $$1, $$2, $$3 }'); \
	sed -i "s/^;; Package-Version: .*/;; Package-Version: $$new/" $(PACKAGE); \
	echo "Package-Version: $$old -> $$new"

