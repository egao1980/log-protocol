(in-package #:log-protocol)

(defclass log-backend () ()
  (:documentation "Base class for log-protocol backends."))

(defclass stream-log-backend (log-backend)
  ((stream :initarg :stream :accessor backend-stream :initform *standard-output*)
   (owns-stream :initarg :owns-stream :accessor %backend-owns-stream-p :initform nil)
   (pattern :initarg :pattern :accessor %backend-pattern :initform nil))
  (:documentation "Simple backend that writes protocol-formatted log records to a stream."))

(defvar *log-backend* nil)
(defvar *log-context* nil)
(defvar *log-layout* :text)
(defvar *log-serdes-format* :json)
(defvar *log-level* :info)

(defparameter *log-pattern* "~a ~a ~a - ~a~@[ ~{~a=~a~^ ~}~]~%")

(defparameter +level-order+
  '((:trace . 0)
    (:debug . 1)
    (:info . 2)
    (:warn . 3)
    (:error . 4)
    (:fatal . 5)))

(defgeneric backend-log (backend level logger-name message &key fields)
  (:documentation "Write MESSAGE at LEVEL for LOGGER-NAME through BACKEND."))

(defun make-stream-log-backend (&key (stream *standard-output*) owns-stream pattern)
  (make-instance 'stream-log-backend
                 :stream stream
                 :owns-stream owns-stream
                 :pattern pattern))

(defun %level-rank (level)
  (or (cdr (assoc level +level-order+))
      (error "Unknown log level ~S" level)))

(defun %enabled-p (level)
  (>= (%level-rank level) (%level-rank *log-level*)))

(defun %level-name (level)
  (string-upcase (symbol-name level)))

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
    (error "Log fields must be key/value pairs, got ~S" fields))
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

(defmethod backend-log ((backend stream-log-backend) level logger-name message &key fields)
  (let* ((stream (backend-stream backend))
         (timestamp (%utc-timestamp))
         (fields (or fields '())))
    (ecase *log-layout*
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
         :format *log-serdes-format*)
        stream)
       (terpri stream)))
    (finish-output stream)))

(defun configure (&key backend level (layout :text) (format :json) stream file pattern)
  "Configure global logging defaults and return the active backend."
  (when level
    (setf *log-level* level))
  (setf *log-layout* layout
        *log-serdes-format* format)
  (when (and stream file)
    (error "Only one of STREAM or FILE may be supplied"))
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
     (%validate-fields *log-context*)
     ,@body))

(defun %log (level message fields)
  (let ((fields (%merge-fields fields)))
    (when (%enabled-p level)
      (backend-log (%ensure-backend) level (%default-logger-name) message :fields fields))))

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
