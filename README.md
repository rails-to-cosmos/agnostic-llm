# agnostic-llm

Claude CLI integration for Emacs.

Drives the [`claude`](https://docs.anthropic.com/en/docs/claude-cli) CLI from
Emacs: per-project terminal sessions, a prompt buffer with `@file` completion,
an inline streaming "bubble", a response viewer, and a FIXME/TODO annotation
system — all gathered under a [`transient`](https://github.com/magit/transient)
menu.

The package name is backend-agnostic by design: `claude` is the first backend,
and the roadmap for driving other agentic CLIs (codex, gemini, ...) from the
same UX lives in [`docs/multi-backend-design.org`](docs/multi-backend-design.org).

## Features

- **Project sessions** — `M-x agnostic-llm` opens a dedicated
  `*llm:PROJECT*` [`vterm`](https://github.com/akermu/emacs-libvterm)
  running `claude`, one per project root. It continues the most recent session
  when one exists.
- **Prompt buffer** — `agnostic-llm-prompt` composes a multi-line prompt with
  `@file` completion (project-relative), auto-prepending file/region context,
  and hands it to the session. Prompts are saved to per-project history.
- **Inline bubble** — a throwaway `claude -p` conversation that streams the
  reply inline, pinned to its own session id, without disturbing the main
  vterm. Promote it (`C-c C-m`) to a full `*llm:PROJECT*` vterm that resumes
  the same session.
- **Response viewer** — `agnostic-llm-show-last-response` renders the latest
  assistant turn (parsed from the session JSONL) into a read-only buffer.
  Nothing is written to disk.
- **Annotations** — drop `FIXME`/`TODO` comments at point, persisted and
  listable per project, and hand the whole set back to Claude to resolve.
- **Model / effort switches** — pick the model and reasoning effort per
  invocation from the menu, or set a persistent default.

## Requirements

- Emacs 28.1+ (built `--with-modules`, for `vterm`)
- [`vterm`](https://github.com/akermu/emacs-libvterm) and
  [`transient`](https://github.com/magit/transient)
- The [`claude`](https://docs.anthropic.com/en/docs/claude-cli) CLI on `PATH`,
  authenticated.

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
         ("C-S-k"   . agnostic-llm-previous-buffer))
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
| `c` | Open Claude in the project vterm    |
| `v` | Vterm in project                    |
| `p` | Prompt buffer                       |
| `P` | Inline prompt (bubble)              |
| `r` | Resume last prompt                  |
| `H` | Prompt history                      |
| `R` | Show last response                  |
| `?` | Describe symbol/region at point     |
| `f` / `t` | Add FIXME / TODO at point     |
| `F` / `T` | List FIXMEs / TODOs           |
| `S` / `D` | Send FIXMEs / TODOs to Claude |
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
| `agnostic-llm`                   | Open / reuse the project's `claude` vterm      |
| `agnostic-llm-menu`              | Transient menu of all commands                 |
| `agnostic-llm-prompt`            | Multi-line prompt buffer (`C-u`: bubble)       |
| `agnostic-llm-prompt-bubble`     | Inline streaming bubble                        |
| `agnostic-llm-prompt-history`    | Browse saved prompts                           |
| `agnostic-llm-prompt-resume`     | Re-open the most recent prompt                 |
| `agnostic-llm-show-last-response`| Render the latest assistant turn               |
| `agnostic-llm-describe-at-point` | Ask Claude about the symbol/region at point    |
| `agnostic-llm-switch-buffer`     | Switch between claude buffers                  |
| `agnostic-llm-next/previous-buffer` | Cycle claude buffers                        |
| `agnostic-llm-set-default-model` | Persist the default model                      |
| `agnostic-llm-add-fixme` / `-todo`  | Annotate at point                           |

## Configuration

```elisp
;; Default model (nil = claude picks). Set from the menu with M, or:
(setq agnostic-llm-model "claude-sonnet-4-6")

;; Teach the package about new models and their effort levels as they
;; ship. Entries are newest-first; the first stands in for claude's
;; default. Every entry must declare its own :efforts; there is no
;; fallback, so an entry without it offers no effort choices.
(add-to-list 'agnostic-llm-models
             '("claude-opus-5" :efforts ("default" "low" "medium" "high" "max" "ultracode")))

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
