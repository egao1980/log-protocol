(defsystem "log-protocol"
  :version "0.1.1"
  :description "CLOS logging protocol for cl-stack (level, filters, async; sinks via backends)"
  :author "egao1980"
  :license "MIT"
  :depends-on ("serdes-protocol" "bordeaux-threads")
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "protocol"))
  :in-order-to ((test-op (test-op "log-protocol/tests"))))

(defsystem "log-protocol/tests"
  :depends-on ("log-protocol" "sexp-protocol" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "log-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
