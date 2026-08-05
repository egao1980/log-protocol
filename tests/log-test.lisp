(in-package #:log-protocol/tests)

(defun contains-substring-p (needle haystack)
  (and (search needle haystack :test #'char=) t))

(defmacro capturing-log-output ((stream &key (layout :text) (format :json) (level :trace)
                                         (async nil) (filters nil))
                                &body body)
  `(let ((log-protocol:*log-backend* nil)
         (log-protocol:*log-context* nil)
         (log-protocol:*log-layout* :text)
         (log-protocol:*log-serdes-format* :json)
         (log-protocol:*log-level* :info)
         (log-protocol:*log-filters* nil)
         (log-protocol:*log-async* nil))
     (unwind-protect
          (with-output-to-string (,stream)
            (log-protocol:configure :stream ,stream
                                    :layout ,layout
                                    :format ,format
                                    :level ,level
                                    :async ,async
                                    :filters ,filters)
            ,@body
            (log-protocol:flush :timeout 2.0))
       (ignore-errors (log-protocol:shutdown-async)))))

(deftest text-info-output
  (let ((line (capturing-log-output (out)
                (log-protocol:info "hello log"))))
    (ok (contains-substring-p "INFO" line))
    (ok (contains-substring-p "hello log" line))))

(deftest with-context-merges-fields
  (let ((line (capturing-log-output (out)
                (log-protocol:with-context (:request-id "abc")
                  (log-protocol:info "context log" :user "nik")))))
    (ok (contains-substring-p "request-id=abc" line))
    (ok (contains-substring-p "user=nik" line))))

(deftest structured-sexp-output
  (sexp-protocol:use-sexp-backend)
  (let ((line (capturing-log-output (out :layout :structured :format :sexp)
                (log-protocol:info "structured log" :answer 42))))
    (ok (contains-substring-p "structured log" line))
    (ok (contains-substring-p "answer" line))))

(deftest level-gate
  (ok (log-protocol:level-enabled-p :error :info))
  (ng (log-protocol:level-enabled-p :debug :info))
  (let ((line (capturing-log-output (out :level :warn)
                (log-protocol:info "hidden")
                (log-protocol:warn "visible"))))
    (ng (contains-substring-p "hidden" line))
    (ok (contains-substring-p "visible" line))))

(deftest filters-drop
  (let ((line (capturing-log-output
                  (out :level :trace
                       :filters (list (lambda (level logger msg fields)
                                        (declare (ignore level logger fields))
                                        (not (search "secret" msg)))))
                (log-protocol:info "secret sauce")
                (log-protocol:info "public ok"))))
    (ng (contains-substring-p "secret" line))
    (ok (contains-substring-p "public ok" line))))

(deftest named-filter-remove
  (let ((log-protocol:*log-filters* nil))
    (log-protocol:add-filter (lambda (l n m f)
                               (declare (ignore l n m f))
                               nil)
                             :name :deny-all)
    (ok (log-protocol:remove-filter :deny-all))
    (ok (null log-protocol:*log-filters*))))

(deftest async-emit
  (let ((line (capturing-log-output (out :async t :level :info)
                (log-protocol:info "async hello"))))
    (ok (contains-substring-p "async hello" line))))
