# log-protocol

CLOS logging protocol for [cl-stack](https://github.com/egao1980/cl-stack).

**Protocol owns:** level gate, filters, async dispatch, layout (text / structured via serdes).  
**Product backends are separate repos.** In-tree: **`stream-log-backend`** (tests / default writer). log4cl / vom live in [`log-backend-log4cl`](https://github.com/egao1980/log-backend-log4cl) and [`log-backend-vom`](https://github.com/egao1980/log-backend-vom).

| System | Role |
|--------|------|
| `log-protocol` (`stack-log`) | API + level / filters / async + stream sink |
| [`log-backend-log4cl`](https://github.com/egao1980/log-backend-log4cl) | default backend (auto-select) |
| [`log-backend-vom`](https://github.com/egao1980/log-backend-vom) | alternate (`use-vom-backend`) |

## Quick use

```lisp
(asdf:load-system "log-backend-log4cl")
(stack-log:configure :level :info :layout :text)
(stack-log:info "started" :port 8080)

;; filter
(stack-log:add-filter (lambda (level logger msg fields)
                        (declare (ignore level logger fields))
                        (not (search "password" msg)))
                      :name :no-secrets)

;; async (protocol mailbox + worker; flush before exit)
(stack-log:configure :async t)
(stack-log:info "queued")
(stack-log:flush)
(stack-log:shutdown-async)
```

Structured:

```lisp
(asdf:load-system "sexp-protocol")
(stack-log:configure :layout :structured :format :sexp)
(stack-log:with-context (:request-id "abc")
  (stack-log:info "handled" :status 200))
```

## License

MIT — see [LICENSE](LICENSE).
