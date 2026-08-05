(in-package #:log-backend-log4cl)

(defclass log4cl-backend (log-protocol:stream-log-backend) ())

(defun make-log4cl-backend (&key (stream *standard-output* stream-supplied-p) file pattern)
  (when (and stream-supplied-p file)
    (error "Only one of STREAM or FILE may be supplied"))
  (make-instance 'log4cl-backend
                 :stream (or (and file
                                  (open file :direction :output
                                             :if-exists :append
                                             :if-does-not-exist :create))
                             stream)
                 :owns-stream (and file t)
                 :pattern pattern))

(defun use-log4cl-backend (&key (stream *standard-output*) file pattern)
  "Bind LOG-PROTOCOL:*LOG-BACKEND* to a log4cl backend instance."
  (setf log-protocol:*log-backend*
        (make-log4cl-backend :stream stream :file file :pattern pattern)))

(use-log4cl-backend)
