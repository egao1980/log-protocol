(defpackage #:log-protocol
  (:use #:cl)
  (:nicknames #:stack-log)
  (:shadow #:trace #:debug #:warn)
  (:export #:log-backend
           #:stream-log-backend
           #:make-stream-log-backend
           #:backend-stream
           #:backend-log
           #:*log-backend*
           #:*log-context*
           #:*log-layout*
           #:*log-serdes-format*
           #:*log-level*
           #:configure
           #:with-context
           #:trace
           #:debug
           #:info
           #:warn
           #:log-error
           #:fatal
           #:log-trace
           #:log-debug
           #:log-info
           #:log-warn
           #:log-fatal))

(in-package #:log-protocol)
