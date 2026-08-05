# log-protocol

Minimal CLOS logging protocol for cl-stack.

| System | Role |
|--------|------|
| `log-protocol` | Logging API, level filtering, text and structured layouts |
| `log-backend-log4cl` | Default stream backend class with `log4cl` dependency; auto-selects on load |
| `log-backend-vom` | Alternate stream backend class with `vom` dependency; selected explicitly |

Nick: `stack-log`.

## Quick use

Text logging:

```lisp
(asdf:load-system "log-backend-log4cl")
(stack-log:configure :level :info :layout :text)
(stack-log:info "started" :port 8080)
(stack-log:log-error "failed" :reason "boom")
```

Structured logging with `serdes-protocol` and `sexp-protocol`:

```lisp
(asdf:load-system "sexp-protocol")
(asdf:load-system "log-protocol")
(sexp-protocol:use-sexp-backend)
(stack-log:configure :layout :structured :format :sexp)
(stack-log:with-context (:request-id "abc")
  (stack-log:info "handled" :status 200))
```

The default structured format is `:json`, but this repository does not ship a JSON backend. Load/register a serdes backend such as json-protocol before using `:json`; tests exercise `:sexp`.

## Local tests

When testing from this workspace, include both sibling repos in ASDF's source registry:

```sh
CL_SOURCE_REGISTRY="/Users/nikolaimatiushev/Projects/cl-workspace/serdes-protocol//:/Users/nikolaimatiushev/Projects/cl-workspace/log-protocol//:"   ros -e '(ql:quickload (quote ("babel" "trivial-gray-streams" "rove")))'       -e '(asdf:test-system "log-protocol")' -q
```

For backend systems, install `log4cl` and/or `vom` via Quicklisp first. CI scripts use cl-repository-client with QL fallbacks for public dependencies; `serdes-protocol` and `sexp-protocol` are first-party systems and should resolve from the registry once published.

## License

MIT -- see [LICENSE](LICENSE).
