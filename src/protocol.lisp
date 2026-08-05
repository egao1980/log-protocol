(in-package #:log-protocol)

;;; ---------------------------------------------------------------------------
;;; Conditions
;;; ---------------------------------------------------------------------------

(define-condition log-misconfiguration (error)
  ((message :initarg :message :reader log-misconfiguration-message))
  (:report (lambda (c s)
             (format s "log misconfiguration: ~a" (log-misconfiguration-message c)))))

;;; ---------------------------------------------------------------------------
;;; Backend (sinks/appenders stay backend-private)
;;; ---------------------------------------------------------------------------

(defclass log-backend () ()
  (:documentation "Base class for log-protocol backends. Appenders/sinks are backend config."))

(defclass stream-log-backend (log-backend)
  ((stream :initarg :stream :accessor backend-stream :initform *standard-output*)
   (owns-stream :initarg :owns-stream :accessor %backend-owns-stream-p :initform nil)
   (pattern :initarg :pattern :accessor %backend-pattern :initform nil))
  (:documentation "Minimal stream sink used by tests and as a default writer."))

(defvar *log-backend* nil)
(defvar *log-context* nil)
(defvar *log-layout* :text)
(defvar *log-serdes-format* :json)
(defvar *log-level* :info
  "Minimum enabled level. Protocol gate before filters/async/backend.")
(defvar *log-filters* nil
  "List of (name . fn) or bare fn. FN(level logger-name message fields) → generalized boolean.
   All must return true to emit. Empty = accept all.")
(defvar *log-async* nil
  "NIL = sync emit. T / :mailbox = queue + worker thread (protocol-owned).")

(defparameter *log-pattern* "~a ~a ~a - ~a~@[ ~{~a=~a~^ ~}~]~%")

(defparameter +level-order+
  '((:trace . 0)
    (:debug . 1)
    (:info . 2)
    (:warn . 3)
    (:error . 4)
    (:fatal . 5)))

(defgeneric backend-log (backend level logger-name message &key fields layout format)
  (:documentation "Write one record. LAYOUT/FORMAT override globals when non-nil (async capture)."))

(defun make-stream-log-backend (&key (stream *standard-output*) owns-stream pattern)
  (make-instance 'stream-log-backend
                 :stream stream
                 :owns-stream owns-stream
                 :pattern pattern))

;;; ---------------------------------------------------------------------------
;;; Level (protocol)
;;; ---------------------------------------------------------------------------

(defun %level-rank (level)
  (or (cdr (assoc level +level-order+ :test #'eq))
      (error 'log-misconfiguration
             :message (format nil "unknown log level ~s" level))))

(defun level-enabled-p (level &optional (min *log-level*))
  "True when LEVEL is at or above MIN (default *LOG-LEVEL*)."
  (>= (%level-rank level) (%level-rank min)))

(defun set-level (level)
  "Set *LOG-LEVEL*. Returns LEVEL."
  (%level-rank level) ; validate
  (setf *log-level* level))

(defun %level-name (level)
  (string-upcase (symbol-name level)))

;;; ---------------------------------------------------------------------------
;;; Filters (protocol)
;;; ---------------------------------------------------------------------------

(defun %filter-fn (entry)
  (if (consp entry) (cdr entry) entry))

(defun %filter-name (entry)
  (when (consp entry) (car entry)))

(defun add-filter (fn &key name)
  "Push FN onto *LOG-FILTERS*. Optional NAME for REMOVE-FILTER. Returns FN."
  (check-type fn (or function symbol))
  (setf *log-filters*
        (cons (if name (cons name fn) fn)
              (if name
                  (remove name *log-filters* :key #'%filter-name :test #'equal)
                  *log-filters*)))
  fn)

(defun remove-filter (name)
  "Remove named filter. Returns T when something was removed."
  (let ((before (length *log-filters*)))
    (setf *log-filters* (remove name *log-filters* :key #'%filter-name :test #'equal))
    (< (length *log-filters*) before)))

(defun clear-filters ()
  (setf *log-filters* nil))

(defun %filters-pass (level logger-name message fields)
  (every (lambda (entry)
           (funcall (%filter-fn entry) level logger-name message fields))
         *log-filters*))

;;; ---------------------------------------------------------------------------
;;; Formatting helpers
;;; ---------------------------------------------------------------------------

(defun %utc-timestamp ()
  (multiple-value-bind (second minute hour day month year)
      (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0d-~2,'0d-~2,'0dT~2,'0d:~2,'0d:~2,'0dZ"
            year month day hour minute second)))

(defun %field-key (key)
  (etypecase key
    (string key)
    (symbol (string-downcase (symbol-name key)))))

(defun %validate-fields (fields)
  (unless (evenp (length fields))
    (error 'log-misconfiguration
           :message (format nil "log fields must be key/value pairs, got ~s" fields)))
  fields)

(defun %merge-fields (fields)
  (%validate-fields *log-context*)
  (%validate-fields fields)
  (append *log-context* fields))

(defun %text-fields (fields)
  (loop for (key value) on fields by #'cddr
        append (list (%field-key key) value)))

(defun %fields-hash (fields)
  (let ((table (make-hash-table :test #'equal)))
    (loop for (key value) on fields by #'cddr
          do (setf (gethash (%field-key key) table) value))
    table))

(defun %structured-record (timestamp level logger-name message fields)
  (let ((record (make-hash-table :test #'equal)))
    (setf (gethash "ts" record) timestamp
          (gethash "level" record) (%level-name level)
          (gethash "logger" record) logger-name
          (gethash "msg" record) message
          (gethash "fields" record) (%fields-hash fields))
    record))

(defun %default-logger-name ()
  (or (and *package* (package-name *package*)) "app"))

(defun %ensure-backend ()
  (or *log-backend*
      (setf *log-backend* (make-stream-log-backend))))

(defmethod backend-log ((backend stream-log-backend) level logger-name message
                        &key fields layout format)
  (let* ((stream (backend-stream backend))
         (timestamp (%utc-timestamp))
         (fields (or fields '()))
         (layout (or layout *log-layout*))
         (format (or format *log-serdes-format*)))
    (ecase layout
      (:text
       (format stream
               (or (%backend-pattern backend) *log-pattern*)
               timestamp
               (%level-name level)
               logger-name
               message
               (%text-fields fields)))
      (:structured
       (write-string
        (serdes-protocol:encode
         (%structured-record timestamp level logger-name message fields)
         :format format)
        stream)
       (terpri stream)))
    (finish-output stream)))

;;; ---------------------------------------------------------------------------
;;; Async (protocol-owned mailbox; sinks stay on backend)
;;; ---------------------------------------------------------------------------

(defvar *%async-lock* nil)
(defvar *%async-queue* nil)
(defvar *%async-cv* nil)
(defvar *%async-thread* nil)
(defvar *%async-running* nil)

(defstruct log-event
  level logger-name message fields layout format backend)

(defun %async-ensure-primitives ()
  (unless *%async-lock*
    (setf *%async-lock* (bt2:make-lock :name "log-protocol-async")
          *%async-cv* (bt2:make-condition-variable :name "log-protocol-async")
          *%async-queue* (list))))

(defun %async-worker ()
  (loop
    (let ((batch nil))
      (bt2:with-lock-held (*%async-lock*)
        (loop until (or (not *%async-running*) *%async-queue*)
              do (bt2:condition-wait *%async-cv* *%async-lock*))
        (when *%async-queue*
          (setf batch (nreverse *%async-queue*)
                *%async-queue* nil))
        (unless (or *%async-running* batch)
          (return-from %async-worker)))
      (dolist (event batch)
        (handler-case
            (backend-log (log-event-backend event)
                         (log-event-level event)
                         (log-event-logger-name event)
                         (log-event-message event)
                         :fields (log-event-fields event)
                         :layout (log-event-layout event)
                         :format (log-event-format event))
          (error (e)
            (format *error-output* "~&log-protocol async emit failed: ~a~%" e)))))))

(defun %ensure-async-worker ()
  (%async-ensure-primitives)
  (bt2:with-lock-held (*%async-lock*)
    (unless *%async-running*
      (setf *%async-running* t
            *%async-thread* (bt2:make-thread #'%async-worker
                                             :name "log-protocol-async")))))

(defun %enqueue (event)
  (%ensure-async-worker)
  (bt2:with-lock-held (*%async-lock*)
    (push event *%async-queue*)
    (bt2:condition-notify *%async-cv*)))

(defun flush (&key (timeout 5.0))
  "Block until the async queue is empty (or TIMEOUT seconds). Sync mode = no-op.
   Returns T if drained, NIL on timeout."
  (unless *log-async*
    (return-from flush t))
  (%async-ensure-primitives)
  (let ((deadline (+ (get-internal-real-time)
                     (floor (* timeout internal-time-units-per-second)))))
    (loop
      (bt2:with-lock-held (*%async-lock*)
        (when (null *%async-queue*)
          (return-from flush t)))
      (when (> (get-internal-real-time) deadline)
        (return-from flush nil))
      (sleep 0.01))))

(defun shutdown-async ()
  "Stop the async worker after draining. Safe to call when async is off."
  (unless *%async-lock*
    (return-from shutdown-async nil))
  (flush :timeout 5.0)
  (let ((thread nil))
    (bt2:with-lock-held (*%async-lock*)
      (setf *%async-running* nil)
      (bt2:condition-notify *%async-cv*)
      (setf thread *%async-thread*
            *%async-thread* nil))
    (when (and thread (bt2:thread-alive-p thread))
      (bt2:join-thread thread)))
  t)

;;; ---------------------------------------------------------------------------
;;; Emit path: level → filters → sync|async → backend
;;; ---------------------------------------------------------------------------

(defun %emit (level logger-name message fields)
  (let ((backend (%ensure-backend))
        (layout *log-layout*)
        (format *log-serdes-format*))
    (if *log-async*
        (%enqueue (make-log-event :level level
                                  :logger-name logger-name
                                  :message message
                                  :fields fields
                                  :layout layout
                                  :format format
                                  :backend backend))
        (backend-log backend level logger-name message
                     :fields fields :layout layout :format format))))

(defun %log (level message fields)
  (let ((fields (%merge-fields fields))
        (logger (%default-logger-name)))
    (when (and (level-enabled-p level)
               (%filters-pass level logger message fields))
      (%emit level logger message fields))))

;;; ---------------------------------------------------------------------------
;;; Configure / context / DX
;;; ---------------------------------------------------------------------------

(defun configure (&key backend level (layout :text) (format :json)
                    stream file pattern
                    (async nil async-p) (filters nil filters-p))
  "Configure protocol gates + layout. STREAM/FILE are convenience sinks only —
   real appenders belong to backend configuration.
   ASYNC = NIL | T | :mailbox. FILTERS replaces *LOG-FILTERS* when supplied."
  (when level
    (set-level level))
  (setf *log-layout* layout
        *log-serdes-format* format)
  (when async-p
    (let ((want (and async t)))
      (when (and *log-async* (not want))
        (shutdown-async))
      (setf *log-async* (cond ((null async) nil)
                              ((member async '(t :mailbox) :test #'eq) t)
                              (t (error 'log-misconfiguration
                                        :message (format nil "async must be nil/t/:mailbox, got ~s" async)))))))
  (when filters-p
    (setf *log-filters*
          (mapcar (lambda (f)
                    (etypecase f
                      (function f)
                      (symbol (symbol-function f))
                      (cons f)))
                  filters)))
  (when (and stream file)
    (error 'log-misconfiguration :message "only one of STREAM or FILE may be supplied"))
  (when pattern
    (setf *log-pattern* pattern))
  (let ((selected
          (cond
            (backend backend)
            (file (make-stream-log-backend
                   :stream (open file :direction :output :if-exists :append :if-does-not-exist :create)
                   :owns-stream t
                   :pattern pattern))
            (stream (make-stream-log-backend :stream stream :pattern pattern))
            ((null *log-backend*) (make-stream-log-backend :pattern pattern))
            (t *log-backend*))))
    (setf *log-backend* selected)))

(defmacro with-context ((&rest fields) &body body)
  `(let ((*log-context* (append *log-context* (list ,@fields))))
     (log-protocol::%validate-fields *log-context*)
     ,@body))

(defun trace (message &rest fields)
  (%log :trace message fields))

(defun debug (message &rest fields)
  (%log :debug message fields))

(defun info (message &rest fields)
  (%log :info message fields))

(defun warn (message &rest fields)
  (%log :warn message fields))

(defun log-error (message &rest fields)
  (%log :error message fields))

(defun fatal (message &rest fields)
  (%log :fatal message fields))

(defun log-trace (message &rest fields)
  (apply #'trace message fields))

(defun log-debug (message &rest fields)
  (apply #'debug message fields))

(defun log-info (message &rest fields)
  (apply #'info message fields))

(defun log-warn (message &rest fields)
  (apply #'warn message fields))

(defun log-fatal (message &rest fields)
  (apply #'fatal message fields))
