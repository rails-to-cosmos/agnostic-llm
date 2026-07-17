# agnostic-llm

Agentic CLI integration for Emacs.

Drives an agentic CLI from Emacs (the
[`claude`](https://docs.anthropic.com/en/docs/claude-cli) CLI by default):
per-project terminal sessions, a prompt buffer with `@file` completion, an
inline streaming "bubble", a response viewer, and a FIXME/TODO annotation
system — all under a [`transient`](https://github.com/magit/transient) menu.

Provider-agnostic: the executable, flags, session-store layout, and
model/effort catalog live in `agnostic-llm-providers`, keyed by
`agnostic-llm-provider`. `claude` is the default; add an entry to drive
another agentic CLI (codex, gemini, ...). Roadmap in
[`docs/multi-backend-design.org`](docs/multi-backend-design.org).

## Features

- **Project sessions** — `M-x agnostic-llm` opens a dedicated
  `*llm:PROJECT*` [`vterm`](https://github.com/akermu/emacs-libvterm)
  running the provider's CLI (`claude` by default), one per project root. It
  continues the most recent session when one exists.
- **Prompt buffer** — `agnostic-llm-prompt` composes a multi-line prompt with
  `@file` completion (project-relative), auto-prepending file/region context,
  and hands it to the session. Prompts are saved to per-project history.
- **Inline bubble** — a throwaway one-shot conversation that streams the
  reply inline, pinned to its own session id, without disturbing the main
  vterm. Promote it (`C-c C-m`) to a full `*llm:PROJECT*` vterm that resumes
  the same session.
- **Response viewer** — `agnostic-llm-show-last-response` renders the latest
  assistant turn (parsed from the session JSONL) into a read-only buffer.
  Nothing is written to disk.
- **Annotations** — drop `FIXME`/`TODO` comments at point, persisted and
  listable per project, and hand the whole set back to the LLM to resolve.
- **Model / effort switches** — pick the model and reasoning effort per
  invocation from the menu, or set a persistent default.

## Requirements

- Emacs 28.1+ (built `--with-modules`, for `vterm`)
- [`vterm`](https://github.com/akermu/emacs-libvterm) and
  [`transient`](https://github.com/magit/transient)
- The active provider's CLI on `PATH`, authenticated (the
  [`claude`](https://docs.anthropic.com/en/docs/claude-cli) CLI by default).

## Installation

### With `use-package` and `:vc`

`agnostic-llm` binds no global keys itself — bind the entry points from your
own config:

```elisp
(use-package agnostic-llm
  :vc (:url "https://github.com/rails-to-cosmos/agnostic-llm.git"
       :branch "master" :rev :newest)
  :bind (("C-x y e" . agnostic-llm-menu)
         ("C-S-j"   . agnostic-llm-next-buffer)
         ("C-S-k"   . agnostic-llm-previous-buffer)
         ("C-x C-x" . agnostic-llm-toggle-vterm-session))
  :config
  (with-eval-after-load 'vterm
    (define-key vterm-mode-map (kbd "C-c C-r")
                #'agnostic-llm-show-last-response)))
```

### Manual

Clone `agnostic-llm` along with its `vterm` and `transient` dependencies, then
add it to your `load-path`:

```elisp
(add-to-list 'load-path "/path/to/agnostic-llm")
(require 'agnostic-llm)
```

## Usage

`M-x agnostic-llm-menu` (the transient) is the hub. Its highlights:

| Key | Action                              |
|-----|-------------------------------------|
| `c` | Open the LLM session in the project vterm |
| `v` | Vterm in project                    |
| `p` | Prompt buffer                       |
| `P` | Inline prompt (bubble)              |
| `r` | Resume last prompt                  |
| `H` | Prompt history                      |
| `R` | Show last response                  |
| `?` | Describe symbol/region at point     |
| `f` / `t` | Add FIXME / TODO at point     |
| `F` / `T` | List FIXMEs / TODOs           |
| `S` / `D` | Send FIXMEs / TODOs to the LLM |
| `G` | Grep TODO/FIXME/HACK/XXX            |

The `-m` (model), `-e` (effort), `-d` (skip permissions), `-c` (current dir),
and `-b` (`/btw` prefix) switches apply to the launched command.

### Prompt and bubble keys

| Key       | Action                                      |
|-----------|---------------------------------------------|
| `C-c C-c` | Send                                        |
| `C-c C-k` | Cancel (kills the bubble subprocess if any) |
| `C-c C-m` | Promote bubble → `*llm:PROJECT*` vterm |

## Commands

| Command                          | Purpose                                        |
|----------------------------------|------------------------------------------------|
| `agnostic-llm`                   | Open / reuse the project's session vterm       |
| `agnostic-llm-menu`              | Transient menu of all commands                 |
| `agnostic-llm-prompt`            | Multi-line prompt buffer (`C-u`: bubble)       |
| `agnostic-llm-prompt-bubble`     | Inline streaming bubble                        |
| `agnostic-llm-prompt-history`    | Browse saved prompts                           |
| `agnostic-llm-prompt-resume`     | Re-open the most recent prompt                 |
| `agnostic-llm-show-last-response`| Render the latest assistant turn               |
| `agnostic-llm-describe-at-point` | Ask the LLM about the symbol/region at point   |
| `agnostic-llm-switch-buffer`     | Switch between LLM buffers                      |
| `agnostic-llm-next/previous-buffer` | Cycle LLM buffers                           |
| `agnostic-llm-toggle-vterm-session` | Toggle `*vterm:*` ↔ `*llm:*`       |
| `agnostic-llm-set-default-model` | Persist the default model                      |
| `agnostic-llm-add-fixme` / `-todo`  | Annotate at point                           |

## Configuration

```elisp
;; Default model (nil = the CLI picks). Set from the menu with M, or:
(setq agnostic-llm-model "claude-sonnet-4-6")

;; CLI-specific settings live in a provider plist; `claude' is the default.
;; Add a model to the claude provider (newest-first; first = CLI default;
;; each entry needs its own :efforts, no fallback):
(push '("claude-opus-5" :efforts ("default" "low" "medium" "high" "max" "ultracode"))
      (plist-get (alist-get 'claude agnostic-llm-providers) :models))

;; Drive a different agentic CLI: register a provider and select it.
(add-to-list 'agnostic-llm-providers
             '(codex
               :executable "codex"     :continue-flag "--continue"
               :print-flag "-p"        :model-flag    "--model"
               :effort-flag "--effort" :session-id-flag "--session"
               :resume-flag "--resume" :dangerous-flag  "--yolo"
               :session-dir "~/.codex/sessions/"
               :session-file-regexp "\\.jsonl\\'" :model-prefix ""
               :models (("gpt-5" :efforts ("default")))))
(setq agnostic-llm-provider 'codex)

;; Files/dirs that mark a project root.
(setq agnostic-llm-project-root-markers '(".git" ".claude" "CLAUDE.md"))

;; Where prompt history and annotations live:
;;   'project -> .agnostic-llm/ inside the repo (.gitignore auto-appended)
;;   'user    -> ~/.cache/agnostic-llm/<repo-id>/
(setq agnostic-llm-persistence-strategy 'project)
```

`M-x customize-group RET agnostic-llm RET` lists everything.

## Development

```sh
make lint     # package-lint + checkdoc (auto-installs package-lint from MELPA)
make compile  # byte-compile with warnings as errors
make test     # run the ERT suite in batch mode
make          # lint + compile + test (mirrors CI)
make patch    # bump Package-Version, ELPA style: MAJOR.MINOR.PATCH.BUILD.YYYYMMDD.REV
              # (also: major, minor, build, rev)
```

Byte-compiling needs `transient` and `vterm` available; `make compile` runs
`package-initialize` so installed packages are on `load-path`.

## License

GPLv3. See file headers and `LICENSE`.
