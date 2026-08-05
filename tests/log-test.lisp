(in-package #:log-protocol/tests)

(defun contains-substring-p (needle haystack)
  (and (search needle haystack :test #'char=) t))

(defmacro capturing-log-output ((stream &key (layout :text) (format :json) (level :trace)) &body body)
  `(let ((log-protocol:*log-backend* nil)
         (log-protocol:*log-context* nil)
         (log-protocol:*log-layout* :text)
         (log-protocol:*log-serdes-format* :json)
         (log-protocol:*log-level* :info))
     (with-output-to-string (,stream)
       (log-protocol:configure :stream ,stream
                               :layout ,layout
                               :format ,format
                               :level ,level)
       ,@body)))

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
