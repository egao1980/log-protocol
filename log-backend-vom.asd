(defsystem "log-backend-vom"
  :version "0.1.0"
  :description "log-protocol backend using vom dependency"
  :author "egao1980"
  :license "MIT"
  :depends-on ("log-protocol" "vom")
  :serial t
  :pathname "src/backend-vom"
  :components ((:file "package")
               (:file "backend")))
