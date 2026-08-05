(in-package #:log-backend-vom)

(defclass vom-backend (log-protocol:stream-log-backend) ())

(defun make-vom-backend (&key (stream *standard-output* stream-supplied-p) file pattern)
  (when (and stream-supplied-p file)
    (error "Only one of STREAM or FILE may be supplied"))
  (make-instance 'vom-backend
                 :stream (or (and file
                                  (open file :direction :output
                                             :if-exists :append
                                             :if-does-not-exist :create))
                             stream)
                 :owns-stream (and file t)
                 :pattern pattern))

(defun use-vom-backend (&key (stream *standard-output*) file pattern)
  "Bind LOG-PROTOCOL:*LOG-BACKEND* to a vom backend instance."
  (setf log-protocol:*log-backend*
        (make-vom-backend :stream stream :file file :pattern pattern)))
