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
           #:*log-filters*
           #:*log-async*

           #:level-enabled-p
           #:set-level
           #:add-filter
           #:remove-filter
           #:clear-filters
           #:flush
           #:shutdown-async

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
           #:log-fatal

           #:log-misconfiguration))

(in-package #:log-protocol)
